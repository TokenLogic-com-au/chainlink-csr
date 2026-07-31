// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CCIPTrustedSenderUpgradeable, Client} from "../ccip/CCIPTrustedSenderUpgradeable.sol";
import {CCIPSenderUpgradeable, CCIPBaseUpgradeable} from "../ccip/CCIPSenderUpgradeable.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {FeeCodec} from "../libraries/FeeCodec.sol";
import {IOraclePool} from "../interfaces/IOraclePool.sol";
import {ICustomSender} from "../interfaces/ICustomSender.sol";

/**
 * @title CustomSender Contract
 * @dev A contract that allows users to swap GHO for sGHO (and vice versa) on deployed chain using a local oracle pool.
 * Users call `deposit` to swap GHO for sGHO, or `redeem` to swap sGHO for GHO, with the rate provided by an oracle.
 * An operator with the `SYNC_ROLE` can call `sync` to send tokens from the oracle pool to the mainnet vault via CCIP,
 * rebalancing the pool so it can continue to honor swaps.
 * This contract can be deployed directly or used as an implementation for a proxy contract (upgradable or not).
 *
 * The contract uses the EIP-7201 to prevent storage collisions.
 */
contract CustomSender is CCIPTrustedSenderUpgradeable, ICustomSender {
    using SafeERC20 for IERC20;

    bytes32 public constant SYNC_ROLE = keccak256("SYNC_ROLE");

    // https://docs.chain.link/ccip/directory/mainnet/chain/mainnet
    uint64 constant ETHEREUM_CHAIN_SELECTOR = 5009297550715157269;

    address public immutable GHO;
    address public immutable SGHO;

    /// @custom:storage-location erc7201:ccip-csr.storage.CustomSender
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
     * @dev Sets the immutable values for {SGHO_TOKEN}, {GHO_TOKEN}, and {CCIP_ROUTER} and the initial values for
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
     * @dev Allows an operator to rebalance the oracle pool by sending the pulled tokens to the mainnet vault via CCIP.
     * The CCIP fee is paid by `msg.sender` and can be paid in GHO or in native token, as encoded in `feeData`.
     * Excess native value sent with the call is refunded to `msg.sender`.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `SYNC_ROLE`.
     * - `amount` must be greater than 0.
     * - `token` must be either `GHO` or `SGHO`.
     * - The oracle pool must be set.
     * - The gas limit encoded in `feeData` must be at least `minProcessMessageGas`.
     * - If `extraArgs` is non-empty, the `gasLimit` it encodes (as `GenericExtraArgsV3`) must also be at least `minProcessMessageGas`.
     *
     * Emits a {Sync} event.
     */
    function sync(
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata feeData,
        bytes calldata extraArgs
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
            feeData,
            extraArgs
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

    /// @inheritdoc ICustomSender
    function refundOraclePool(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, CustomSenderZeroAmount());
        require(token == GHO || token == SGHO, CustomSenderInvalidToken());

        address oraclePool = _getCustomSenderStorage().oraclePool;
        require(oraclePool != address(0), CustomSenderOraclePoolNotSet());

        IERC20(token).safeTransfer(oraclePool, amount);

        emit OraclePoolRefunded(oraclePool, token, amount);
    }

    /**
     * @dev Sets the address of the oracle pool.
     * It also approves the maximum amount of `GHO` to the oracle pool and revokes the approval from the previous oracle pool.
     * It also approves the maximum amount of `SGHO` to the oracle pool and revokes the approval from the previous oracle pool.
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

    /**
     * @dev Sets the address of the mainnet vault.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     *
     * Emits a {VaultSet} event.
     */
    function setVault(address vault) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVault(vault);
    }

    /**
     * @dev Returns the address of the oracle pool.
     */
    function getOraclePool() public view returns (address) {
        return _getCustomSenderStorage().oraclePool;
    }

    /**
     * @dev Returns the address of the mainnet vault.
     */
    function getVault() public view returns (address) {
        return _getCustomSenderStorage().vault;
    }

    function _buildAndSendSync(
        uint64 destChainSelector,
        address token,
        uint256 amount,
        uint256 minimumAmountOut,
        bytes calldata feeData,
        bytes calldata extraArgs
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

        require(gasLimit >= minProcessMessageGas, CCIPSenderInsufficientGas());

        return
            _ccipSend(
                destChainSelector,
                tokenAmounts,
                payInGho,
                maxFee,
                gasLimit,
                data,
                extraArgs
            );
    }

    /**
     * @dev Sets the address of the oracle pool.
     *
     * Emits a {OraclePoolSet} event.
     */
    function _setOraclePool(address oraclePool) internal virtual {
        CustomSenderStorage storage $ = _getCustomSenderStorage();
        address oldOracle = $.oraclePool;

        $.oraclePool = oraclePool;

        if (oldOracle != address(0)) {
            IERC20(GHO).approve(oldOracle, 0);
            IERC20(SGHO).approve(oldOracle, 0);
        }

        if (oraclePool != address(0)) {
            IERC20(GHO).approve(oraclePool, type(uint256).max);
            IERC20(SGHO).approve(oraclePool, type(uint256).max);
        }

        emit OraclePoolSet(oldOracle, oraclePool);
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
