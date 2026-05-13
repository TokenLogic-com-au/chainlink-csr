// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CCIPTrustedSenderUpgradeable, Client} from "../ccip/CCIPTrustedSenderUpgradeable.sol";
import {CCIPSenderUpgradeable, CCIPBaseUpgradeable} from "../ccip/CCIPSenderUpgradeable.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {ExtraArgsCodec} from "../libraries/ExtraArgsCodec.sol";
import {FeeCodec} from "../libraries/FeeCodec.sol";
import {IOraclePool} from "../interfaces/IOraclePool.sol";
import {ICustomSender} from "../interfaces/ICustomSender.sol";

/**
 * @title CustomSender Contract
 * @dev A contract that allows users to stake (W)Native to receive a staked token that isn't native to this chain.
 * The slow staking function allows users to send (W)Native to the receiver contract on the main chain, mint the native staked
 * token and send it back to the user on this chain.
 * The fast staking function allows users to swap (W)Native for the native staked token using an oracle pool.
 * Then an operator can synchronize this chain by sending the native tokens to the receiver contract on the main chain,
 * mint the native staked token and send it back to the oracle pool on this chain.
 * This contract can be deployed directly or used as an implementation for a proxy contract (upgradable or not).
 *
 * The contract uses the EIP-7201 to prevent storage collisions.
 */
contract CustomSender is CCIPTrustedSenderUpgradeable, ICustomSender {
    using SafeERC20 for IERC20;

    /* The minimum gas to process the message. */
    uint32 public constant MIN_PROCESS_MESSAGE_GAS = 75_000;

    bytes32 public constant SYNC_ROLE = keccak256("SYNC_ROLE");

    // https://docs.chain.link/ccip/directory/mainnet/chain/mainnet
    uint64 constant ETHEREUM_CHAIN_SELECTOR = 5009297550715157269;

    address public immutable GHO;
    address public immutable SGHO;

    /* @custom:storage-location erc7201:ccip-csr.storage.CustomSender */
    struct CustomSenderStorage {
        address oraclePool;
        address vault;
    }

    // keccak256(abi.encode(uint256(keccak256("ccip-csr.storage.CustomSender")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CustomSenderStorageLocation =
        0x8d7d6771bb1753c5a4765d77340d4f09d4dc8da64869871a1bdb7f28bcfa7400;

    function _getCustomSenderStorage()
        private
        pure
        returns (CustomSenderStorage storage $)
    {
        assembly {
            $.slot := CustomSenderStorageLocation
        }
    }

    /**
     * @dev Sets the immutable values for {TOKEN}, {GHO_TOKEN}, and {CCIP_ROUTER} and the initial values for
     * the oracle pool and the admin role.
     */
    constructor(
        address sghoToken,
        address ghoToken,
        address ccipRouter,
        address oraclePool,
        address vault,
        address initialAdmin
    ) CCIPSenderUpgradeable(ghoToken) CCIPBaseUpgradeable(ccipRouter) {
        require(
            sghoToken != address(0) &&
                ghoToken != address(0) &&
                sghoToken != ghoToken,
            CustomSenderInvalidParameters()
        );

        GHO = ghoToken;
        SGHO = sghoToken;

        initialize(oraclePool, vault, initialAdmin);
    }

    /**
     * @dev Initializes the values for the oracle pool and the admin role.
     * If this contract isn't used as the implementation for a proxy contract, this function will be called by the constructor.
     */
    function initialize(
        address oraclePool,
        address vault,
        address initialAdmin
    ) public initializer {
        require(initialAdmin != address(0), CustomSenderInvalidParameters());

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setOraclePool(oraclePool);
        _setVault(vault);
    }

    /**
     * @dev Allows users to swap GHO for sGHO using an oracle pool.
     * The user sends GHO to this contract, the oracle pool swaps the GHO for sGHO,
     * and sends the sGHO back to the user.
     *
     * Requirements:
     *
     * - The amount sent must be greater than 0.
     * - The token sent must be GHO.
     *
     * Emits a {Deposit} event.
     */
    function deposit(
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public virtual returns (uint256) {
        require(exactAmountIn > 0, CustomSenderZeroAmount());

        address oraclePool = _getCustomSenderStorage().oraclePool;
        require(oraclePool != address(0), CustomSenderOraclePoolNotSet());

        IERC20(GHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(GHO).forceApprove(oraclePool, exactAmountIn);

        uint256 amountOut = IOraclePool(oraclePool).deposit(
            msg.sender,
            exactAmountIn,
            minAmountOut
        );

        emit Deposit(msg.sender, GHO, exactAmountIn, amountOut);

        return amountOut;
    }

    /**
     * @dev Allows users to swap sGHO for GHO using an oracle pool.
     * The user sends sGHO to this contract, the oracle pool swaps the sGHO for GHO,
     * and sends the GHO back to the user.
     *
     * Requirements:
     *
     * - The amount sent must be greater than 0.
     * - The token sent must be sGHO.
     *
     * Emits a {Redeem} event.
     */
    function redeem(
        uint256 amount,
        uint256 minAmountOut
    ) public virtual returns (uint256) {
        require(amount > 0, CustomSenderZeroAmount());

        address oraclePool = _getCustomSenderStorage().oraclePool;
        require(oraclePool != address(0), CustomSenderOraclePoolNotSet());

        IERC20(SGHO).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(SGHO).forceApprove(oraclePool, amount);

        uint256 amountOut = IOraclePool(oraclePool).redeem(
            msg.sender,
            amount,
            minAmountOut
        );

        emit Redeem(msg.sender, SGHO, amount, amountOut);

        return amountOut;
    }

    /**
     * @dev Allows the operator to synchronize this chain by sending the native tokens to the receiver contract on the main chain,
     * mint the native staked token and send it back to the oracle pool on this chain.
     * The operator has to pay the gas fee for the CCIP message and for the way back.
     * It is very important that the `feeOtoD` is sufficient to cover the gas fee for the way back, or the tokens may
     * get stuck depending on the bridge used for the way back.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `SYNC_ROLE`.
     *
     * Emits a {Sync} event.
     */
    function sync(
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata feeData
    ) external payable virtual onlyRole(SYNC_ROLE) returns (bytes32) {
        require(amount > 0, CustomSenderZeroAmount());
        require(token == GHO || token == SGHO, CustomSenderInvalidToken());

        address oraclePool = _getCustomSenderStorage().oraclePool;

        require(oraclePool != address(0), CustomSenderOraclePoolNotSet());

        IOraclePool(oraclePool).pull(token, amount);

        bytes32 messageId = _buildAndSendSync(
            ETHEREUM_CHAIN_SELECTOR,
            token,
            amount,
            minAmountOut,
            feeData
        );

        TokenHelper.refundExcessNative(msg.sender);

        emit Sync(
            msg.sender,
            ETHEREUM_CHAIN_SELECTOR,
            messageId,
            token,
            amount
        );

        return messageId;
    }

    /**
     * @dev Sets the address of the oracle pool.
     * It also approves the maximum amount of WNative to the oracle pool and revokes the approval from the previous oracle pool.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     *
     * Emits a {OraclePoolSet} event.
     */
    function setOraclePool(
        address oraclePool
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setOraclePool(oraclePool);
    }

    function setVault(address vault) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVault(vault);
    }

    /**
     * @dev Returns the address of the oracle pool.
     */
    function getOraclePool() public view returns (address) {
        return _getCustomSenderStorage().oraclePool;
    }

    function getVault() public view returns (address) {
        return _getCustomSenderStorage().vault;
    }

    function _buildAndSendSync(
        uint64 destChainSelector,
        address token,
        uint256 amount,
        uint256 minimumAmountOut,
        bytes calldata feeData
    ) internal virtual returns (bytes32) {
        CustomSenderStorage storage $ = _getCustomSenderStorage();

        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        bytes memory data = abi.encode(
            $.vault,
            bytes32(uint256(uint160($.oraclePool))),
            minimumAmountOut,
            true
        );

        (uint256 maxFee, bool payInGho, uint256 gasLimit) = FeeCodec.decodeCCIP(
            feeData
        );

        require(
            gasLimit >= MIN_PROCESS_MESSAGE_GAS,
            CustomSenderInsufficientGas()
        );

        return
            _ccipSend(
                destChainSelector,
                tokenAmounts,
                payInGho,
                maxFee,
                gasLimit,
                data
            );
    }

    /**
     * @dev Sets the address of the oracle pool.
     *
     * Emits a {OraclePoolSet} event.
     */
    function _setOraclePool(address oraclePool) internal virtual {
        CustomSenderStorage storage $ = _getCustomSenderStorage();
        $.oraclePool = oraclePool;

        emit OraclePoolSet(oraclePool);
    }

    /**
     * @dev Sets the address of the mainnet vault.
     *
     * Emits a {VaultSet} event.
     */
    function _setVault(address vault) internal {
        require(vault != address(0), CustomSenderZeroAddress());

        CustomSenderStorage storage $ = _getCustomSenderStorage();
        $.vault = vault;
        emit VaultSet(vault);
    }
}
