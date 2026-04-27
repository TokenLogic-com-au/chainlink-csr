// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CCIPTrustedSenderUpgradeable, Client} from "../ccip/CCIPTrustedSenderUpgradeable.sol";
import {CCIPSenderUpgradeable, CCIPBaseUpgradeable} from "../ccip/CCIPSenderUpgradeable.sol";
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

    address public immutable GHO;
    address public immutable SGHO;

    /* @custom:storage-location erc7201:ccip-csr.storage.CustomSender */
    struct CustomSenderStorage {
        address oraclePool;
        address vault;
        address supplyOracle;
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
        address initialAdmin
    ) CCIPSenderUpgradeable(ghoToken) CCIPBaseUpgradeable(ccipRouter) {
        if (
            sghoToken == address(0) ||
            ghoToken == address(0) ||
            sghoToken == ghoToken
        ) {
            revert CustomSenderInvalidParameters();
        }

        GHO = ghoToken;
        SGHO = sghoToken;

        initialize(oraclePool, initialAdmin);
    }

    /**
     * @dev Initializes the values for the oracle pool and the admin role.
     * If this contract isn't used as the implementation for a proxy contract, this function will be called by the constructor.
     */
    function initialize(
        address oraclePool,
        address initialAdmin
    ) public initializer {
        if (initialAdmin == address(0)) revert CustomSenderInvalidParameters();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setOraclePool(oraclePool);
    }

    /**
     * @dev Allows users to swap (W)Native for the native staked token using an oracle pool.
     * The user sends (W)Native to this contract, the oracle pool swaps the (W)Native for the native staked token,
     * and sends the native staked token back to the user.
     *
     * Requirements:
     *
     * - The amount sent must be greater than 0.
     * - The token sent must be the wrapped native token or native token.
     *
     * Emits a {Deposit} event.
     */
    function deposit(
        uint256 amount,
        uint256 minAmountOut
    ) public virtual returns (uint256) {
        if (amount == 0) revert CustomSenderZeroAmount();

        address oraclePool = _getCustomSenderStorage().oraclePool;
        if (oraclePool == address(0)) revert CustomSenderOraclePoolNotSet();

        _pullFrom(GHO, msg.sender, amount);

        IERC20(GHO).forceApprove(oraclePool, amount);

        uint256 amountOut = IOraclePool(oraclePool).deposit(
            msg.sender,
            amount,
            minAmountOut
        );

        emit Deposit(msg.sender, GHO, amount, amountOut);

        return amountOut;
    }

    function redeem(
        uint256 amount,
        uint256 minAmountOut
    ) public virtual returns (uint256) {
        if (amount == 0) revert CustomSenderZeroAmount();

        address oraclePool = _getCustomSenderStorage().oraclePool;
        if (oraclePool == address(0)) revert CustomSenderOraclePoolNotSet();

        _pullFrom(SGHO, msg.sender, amount);

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
        uint64 destChainSelector,
        address token,
        uint256 amount,
        uint256 minimumAmountOut,
        bytes calldata feeOtoD,
        bytes calldata extraArgs
    ) external virtual onlyRole(SYNC_ROLE) returns (bytes32) {
        if (amount == 0) revert CustomSenderZeroAmount();
        if (token != GHO && token != SGHO) revert CustomSenderInvalidToken();

        CustomSenderStorage storage $ = _getCustomSenderStorage();

        if ($.oraclePool == address(0) || $.supplyOracle == address(0)) {
            revert CustomSenderOraclePoolNotSet();
        }

        // if (ISupplyOracle($.supplyOracle).capacityReached()) revert MaxSupplyReached();

        IOraclePool($.oraclePool).pull(token, amount);

        bytes32 messageId = _buildAndSendSync(
            destChainSelector,
            token,
            amount,
            minimumAmountOut,
            feeOtoD,
            extraArgs
        );

        emit Sync(msg.sender, destChainSelector, messageId, token, amount);

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

    function setSupplyOracle(
        address oracle
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _getCustomSenderStorage().supplyOracle = oracle;
        emit SupplyOracleSet(oracle);
    }

    function setVault(address vault) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _getCustomSenderStorage().vault = vault;
        emit VaultSet(vault);
    }

    /**
     * @dev Returns the address of the oracle pool.
     */
    function getOraclePool() public view returns (address) {
        return _getCustomSenderStorage().oraclePool;
    }

    function getSupplyOracle() public view returns (address) {
        return _getCustomSenderStorage().supplyOracle;
    }

    function getVault() public view returns (address) {
        return _getCustomSenderStorage().vault;
    }

    function _buildAndSendSync(
        uint64 destChainSelector,
        address token,
        uint256 amount,
        uint256 minimumAmountOut,
        bytes calldata feeOtoD,
        bytes calldata extraArgs
    ) internal virtual returns (bytes32) {
        CustomSenderStorage storage $ = _getCustomSenderStorage();

        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        bytes memory data = abi.encode(
            $.vault,
            $.oraclePool,
            minimumAmountOut,
            true,
            extraArgs
        );

        (uint256 maxFee, bool payInGho, uint256 gasLimit) = FeeCodec.decodeCCIP(
            feeOtoD
        );

        if (gasLimit < MIN_PROCESS_MESSAGE_GAS)
            revert CustomSenderInsufficientGas();

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
     * @dev Pulls `amount` of `token` from `user` and sends them to this contract.
     *
     * Requirements:
     *
     * - `amount` must be greater than 0.
     */
    function _pullFrom(
        address token,
        address user,
        uint256 amount
    ) internal virtual {
        if (amount > 0) {
            IERC20(token).safeTransferFrom(user, address(this), amount);
        }
    }
}
