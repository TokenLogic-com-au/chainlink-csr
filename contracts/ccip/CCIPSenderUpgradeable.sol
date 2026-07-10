// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {ExtraArgsCodec} from "../libraries/ExtraArgsCodec.sol";
import {CCIPBaseUpgradeable} from "./CCIPBaseUpgradeable.sol";
import {ICCIPSenderUpgradeable} from "../interfaces/ICCIPSenderUpgradeable.sol";

/**
 * @title CCIPSenderUpgradeable Contract
 * @dev The base contract for all CCIP sender contracts.
 * It provides the ability to send messages to the CCIP router using the `ccipSend` function.
 * Each message can contain zero, one, or multiple (token, amount) pairs.
 */
abstract contract CCIPSenderUpgradeable is
    CCIPBaseUpgradeable,
    ICCIPSenderUpgradeable
{
    using SafeERC20 for IERC20;

    address public immutable override GHO_TOKEN;

    /// @dev The minimum gas that must be encoded in `extraArgs` (or in the fallback `gasLimit`
    /// passed by the derived sender) for the destination chain to execute the message. Defaults to
    /// 400,000. Admin-tunable via {setMinProcessMessageGas} so it can track destination-chain changes.
    uint32 public minProcessMessageGas = 400_000;

    /**
     * @dev Sets the immutable value for {GHO_TOKEN}.
     */
    constructor(address ghoToken) {
        require(ghoToken != address(0), CCIPSenderInvalidParameters());

        GHO_TOKEN = ghoToken;
    }

    function __CCIPSender_init() internal onlyInitializing {}

    function __CCIPSender_init_unchained() internal onlyInitializing {}

    /**
     * @dev Updates the minimum gas required to process the message on the destination chain.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     * - `gasLimit` must be non-zero — a zero value would disable the guard and let low-gas messages through.
     *
     * Emits a {MinProcessMessageGasSet} event.
     * @param gasLimit The new minimum gas limit.
     */
    function setMinProcessMessageGas(
        uint32 gasLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(gasLimit > 0, CCIPSenderInvalidGasLimit());

        uint32 oldGasLimit = minProcessMessageGas;
        minProcessMessageGas = gasLimit;

        emit MinProcessMessageGasSet(oldGasLimit, gasLimit);
    }

    /**
     * @dev Sends a message to the CCIP router.
     * The message can contain zero, one, or multiple (token, amount) pairs.
     * This function will calculate the exact fee required for the message and forward it to the router.
     * The fee can be paid in GHO or native token.
     *
     * Requirements:
     *
     * - `receiver` must not be empty.
     * - `maxFee` must be greater than or equal to the fee for the message.
     * - each token in `tokenAmounts` must have been transferred to the contract.
     * - if `payInGho` is `true`: `payer` must have approved this contract to transfer the fee in GHO, unless
     *   `payer` is the contract itself, in which case the contract must hold at least the fee in GHO.
     * - if `payInGho` is `false`: `msg.value` must be greater than or equal to the fee.
     */
    function _ccipSendTo(
        uint64 destChainSelector,
        address payer,
        bytes memory receiver,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bool payInGho,
        uint256 maxFee,
        uint256 gasLimit,
        bytes memory data,
        bytes calldata extraArgs
    ) internal virtual returns (bytes32) {
        require(receiver.length > 0, CCIPSenderEmptyReceiver());

        {
            uint256 length = tokenAmounts.length;
            for (uint256 i = 0; i < length; ++i) {
                address token = tokenAmounts[i].token;
                uint256 amount = tokenAmounts[i].amount;

                require(
                    amount > 0 && token != address(0),
                    CCIPSenderInvalidTokenAmount()
                );

                IERC20(token).safeIncreaseAllowance(CCIP_ROUTER, amount);
            }
        }

        if (extraArgs.length > 0) {
            ExtraArgsCodec.GenericExtraArgsV3 memory args = abi.decode(
                extraArgs[4:],
                (ExtraArgsCodec.GenericExtraArgsV3)
            );

            require(
                args.gasLimit >= minProcessMessageGas,
                CCIPSenderInsufficientGas()
            );
        }

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: receiver,
            data: data,
            tokenAmounts: tokenAmounts,
            feeToken: payInGho ? GHO_TOKEN : address(0),
            extraArgs: extraArgs.length > 0
                ? extraArgs
                : Client._argsToBytes(
                    Client.EVMExtraArgsV1({gasLimit: gasLimit})
                )
        });

        uint256 nativeFee = 0;

        {
            uint256 fee = IRouterClient(CCIP_ROUTER).getFee(
                destChainSelector,
                message
            );
            require(fee <= maxFee, CCIPSenderExceedsMaxFee(fee, maxFee));

            if (payInGho) {
                if (payer != address(this)) {
                    IERC20(GHO_TOKEN).safeTransferFrom(
                        payer,
                        address(this),
                        fee
                    );
                }
                IERC20(GHO_TOKEN).safeIncreaseAllowance(CCIP_ROUTER, fee);
            } else {
                nativeFee = fee;
            }
        }

        return
            IRouterClient(CCIP_ROUTER).ccipSend{value: nativeFee}(
                destChainSelector,
                message
            );
    }
}
