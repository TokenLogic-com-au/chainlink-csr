// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CCIPTrustedSenderUpgradeable, Client} from "../ccip/CCIPTrustedSenderUpgradeable.sol";
import {CCIPSenderUpgradeable, CCIPBaseUpgradeable} from "../ccip/CCIPSenderUpgradeable.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {FeeCodec} from "../libraries/FeeCodec.sol";
import {IOraclePool} from "../interfaces/IOraclePool.sol";
import {ISwapHandler} from "../interfaces/ISwapHandler.sol";

/**
 * @title SwapHandler Contract
 * @dev A contract that allows users to swap GHO for sGHO (and vice versa) on deployed chain using a local oracle pool.
 * Users call `deposit` to swap GHO for sGHO, or `redeem` to swap sGHO for GHO, with the rate provided by an oracle.
 * An operator with the `SYNC_ROLE` can call `sync` to send tokens from the oracle pool to the mainnet vault via CCIP,
 * rebalancing the pool so it can continue to honor swaps.
 * This contract can be deployed directly or used as an implementation for a proxy contract (upgradable or not).
 *
 * The contract uses EIP-7201 to prevent storage collisions.
 */
contract SwapHandler is CCIPTrustedSenderUpgradeable, ISwapHandler {
    using SafeERC20 for IERC20;

    /// @inheritdoc ISwapHandler
    bytes32 public constant SYNC_ROLE = keccak256("SYNC_ROLE");

    /// @dev The CCIP chain selector of the Ethereum mainnet destination chain.
    /// https://docs.chain.link/ccip/directory/mainnet/chain/mainnet
    uint64 constant ETHEREUM_CHAIN_SELECTOR = 5009297550715157269;

    /// @inheritdoc ISwapHandler
    address public immutable GHO;

    /// @inheritdoc ISwapHandler
    address public immutable SGHO;

    /// @dev The storage layout for the {SwapHandler} contract.
    /// @custom:storage-location erc7201:ccip-csr.storage.SwapHandler
    /// @param oraclePool The address of the oracle pool used to swap `GHO` and `SGHO`.
    /// @param vault The address of the mainnet vault that receives synced tokens.
    struct SwapHandlerStorage {
        address oraclePool;
        address vault;
        address localRefundAddress;
    }

    /// @dev The ERC-7201 storage location for the {SwapHandlerStorage} struct.
    /// keccak256(abi.encode(uint256(keccak256("ccip-csr.storage.SwapHandler")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SwapHandlerStorageLocation =
        0x3c32139014b4e851cb2e6374c79ea0bb757c673e965891f100349a1f9bf7d500;

    /// @dev Returns a storage pointer to the {SwapHandlerStorage} struct.
    /// @return $ The storage pointer to the {SwapHandlerStorage} struct.
    function _getSwapHandlerStorage()
        private
        pure
        returns (SwapHandlerStorage storage $)
    {
        assembly {
            $.slot := SwapHandlerStorageLocation
        }
    }

    /**
     * @dev Sets the immutable values for {SGHO}, {GHO}, and the CCIP router and the initial values for
     * the oracle pool, the mainnet vault and the admin role.
     * @param sghoToken The address of the `SGHO` token on the deployed network.
     * @param ghoToken The address of the `GHO` token on the deployed network.
     * @param ccipRouter The address of the CCIP router.
     * @param oraclePool The address of the oracle pool.
     * @param vault The address of the mainnet vault.
     * @param initialAdmin The address granted the `DEFAULT_ADMIN_ROLE`.
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
            SwapHandlerInvalidParameters()
        );

        GHO = ghoToken;
        SGHO = sghoToken;

        initialize(oraclePool, vault, initialAdmin);
    }

    /**
     * @dev Initializes the values for the oracle pool, the mainnet vault and the admin role.
     * If this contract isn't used as the implementation for a proxy contract, this function will be called by the constructor.
     * @param oraclePool The address of the oracle pool.
     * @param vault The address of the mainnet vault.
     * @param initialAdmin The address granted the `DEFAULT_ADMIN_ROLE`.
     */
    function initialize(
        address oraclePool,
        address vault,
        address initialAdmin
    ) public initializer {
        require(initialAdmin != address(0), SwapHandlerInvalidParameters());

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setOraclePool(oraclePool);
        _setVault(vault);
        minProcessMessageGas = 400_000;
    }

    /// @inheritdoc ISwapHandler
    function deposit(
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public returns (uint256) {
        require(exactAmountIn > 0, SwapHandlerZeroAmount());

        address oraclePool = _getSwapHandlerStorage().oraclePool;
        require(oraclePool != address(0), SwapHandlerOraclePoolNotSet());

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

    /// @inheritdoc ISwapHandler
    function redeem(
        uint256 amount,
        uint256 minAmountOut
    ) public returns (uint256) {
        require(amount > 0, SwapHandlerZeroAmount());

        address oraclePool = _getSwapHandlerStorage().oraclePool;
        require(oraclePool != address(0), SwapHandlerOraclePoolNotSet());

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

    /// @inheritdoc ISwapHandler
    function sync(
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata feeData,
        bytes calldata extraArgs
    ) external payable onlyRole(SYNC_ROLE) returns (bytes32) {
        require(amount > 0, SwapHandlerZeroAmount());
        require(token == GHO || token == SGHO, SwapHandlerInvalidToken());

        address oraclePool = _getSwapHandlerStorage().oraclePool;

        require(oraclePool != address(0), SwapHandlerOraclePoolNotSet());

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

    /// @inheritdoc ISwapHandler
    function refundOraclePool(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, SwapHandlerZeroAmount());
        require(token == GHO || token == SGHO, SwapHandlerInvalidToken());

        address oraclePool = _getSwapHandlerStorage().oraclePool;
        require(oraclePool != address(0), SwapHandlerOraclePoolNotSet());

        IERC20(token).safeTransfer(oraclePool, amount);

        emit OraclePoolRefunded(oraclePool, token, amount);
    }

    /// @inheritdoc ISwapHandler
    function setOraclePool(
        address oraclePool
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setOraclePool(oraclePool);
    }

    /// @inheritdoc ISwapHandler
    function setVault(address vault) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVault(vault);
    }

    /// @inheritdoc ISwapHandler
    function setLocalRefundAddress(
        address refundAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLocalRefundAddress(refundAddress);
    }

    /// @inheritdoc ISwapHandler
    function getOraclePool() public view returns (address) {
        return _getSwapHandlerStorage().oraclePool;
    }

    /// @inheritdoc ISwapHandler
    function getVault() public view returns (address) {
        return _getSwapHandlerStorage().vault;
    }

    /**
     * @dev Builds the CCIP message for a sync and sends it to the destination chain via the CCIP router.
     * The gas limit encoded in `feeData` must be at least {minProcessMessageGas}, otherwise the call reverts
     * with `SwapHandlerInsufficientGas`. The gas limit embedded in `extraArgs`, when one is supplied, is
     * checked separately by `CCIPSenderUpgradeable` against the same floor.
     * @param destChainSelector The CCIP selector of the destination chain.
     * @param token The address of the token to be sent (`GHO` or `SGHO`).
     * @param amount The amount of `token` to be sent.
     * @param minimumAmountOut The minimum amount expected on the destination chain.
     * @param feeData The encoded CCIP fee data (max fee, fee payment token, and gas limit).
     * @param extraArgs The extra arguments forwarded to the CCIP router.
     * @return The identifier of the CCIP message sent.
     */
    function _buildAndSendSync(
        uint64 destChainSelector,
        address token,
        uint256 amount,
        uint256 minimumAmountOut,
        bytes calldata feeData,
        bytes calldata extraArgs
    ) internal virtual returns (bytes32) {
        SwapHandlerStorage storage $ = _getSwapHandlerStorage();

        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        bytes memory data = abi.encode(
            $.vault,
            bytes32(uint256(uint160($.oraclePool))),
            minimumAmountOut,
            _packDeliveryAndRefund(true)
        );

        (uint256 maxFee, bool payInGho, uint256 gasLimit) = FeeCodec.decodeCCIP(
            feeData
        );

        require(gasLimit >= minProcessMessageGas, SwapHandlerInsufficientGas());

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
     * @dev Packs a local refund address (address(0) is non-returnable locally) with boolean on whether
     * to return to source chain or not. In case of a misconfiguration, could help to have a local (destination) address
     * for refunds instead of returning to source chain.
     * @param returnToSourceChain Whether to return failed messages to source chain
     */
    function _packDeliveryAndRefund(
        bool returnToSourceChain
    ) internal view returns (uint256) {
        return
            (uint256(uint160(_getSwapHandlerStorage().localRefundAddress)) <<
                1) | (returnToSourceChain ? 1 : 0);
    }

    /**
     * @dev Sets the address of the oracle pool.
     * It approves the maximum amount of `GHO` and `SGHO` to the new oracle pool and revokes the
     * approvals from the previous oracle pool.
     *
     * Emits an {OraclePoolSet} event.
     *
     * @param oraclePool The address of the new oracle pool.
     */
    function _setOraclePool(address oraclePool) internal virtual {
        SwapHandlerStorage storage $ = _getSwapHandlerStorage();
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
     *
     * @param vault The address of the new mainnet vault.
     */
    function _setVault(address vault) internal {
        require(vault != address(0), SwapHandlerZeroAddress());

        SwapHandlerStorage storage $ = _getSwapHandlerStorage();
        $.vault = vault;
        emit VaultSet(vault);
    }

    /**
     * @dev Sets the local refund address of the destination chain.
     *
     * Emits a {LocalRefundAddressSet} event.
     */
    function _setLocalRefundAddress(address refundAddress) internal {
        SwapHandlerStorage storage $ = _getSwapHandlerStorage();
        address oldRefundAddress = $.localRefundAddress;

        $.localRefundAddress = refundAddress;

        emit LocalRefundAddressSet(oldRefundAddress, refundAddress);
    }
}
