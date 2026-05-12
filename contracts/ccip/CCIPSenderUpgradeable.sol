// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

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
     * @dev Sends a message to the CCIP router.
     * The message can contain zero, one, or multiple (token, amount) pairs.
     * This function will calculate the exact fee required for the message and forward it to the router.
     * The fee can be paid in GHO or native token.
     *
     * Requirements:
     *
     * - `receiver` must be a non-empty array.
     * - `maxFee` must be greater than or equal to the fee for the message.
     * - if `payInGho` is `true`, `msg.sender` must have approved the contract to transfer `maxFee` of GHO. Else,
     *   `msg.value` must be greater than or equal to the fee for the message.
     * - each token in `tokenAmounts` must have been transferred to the contract.
     * - payer must have approved the contract to transfer the fee in GHO if `payInGho` is `true`, unless `payer` is
     *   the contract itself, in which case the contract must have enough GHO.
     */
    function _ccipSendTo(
        uint64 destChainSelector,
        address payer,
        bytes memory receiver,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bool payInGho,
        uint256 maxFee,
        uint256 gasLimit,
        bytes memory data
    ) internal virtual returns (bytes32) {
        require(receiver.length > 0, CCIPSenderEmptyReceiver());

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

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: receiver,
            data: data,
            tokenAmounts: tokenAmounts,
            feeToken: payInGho ? GHO_TOKEN : address(0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: gasLimit})
            )
        });

        uint256 fee = IRouterClient(CCIP_ROUTER).getFee(
            destChainSelector,
            message
        );
        require(fee <= maxFee, CCIPSenderExceedsMaxFee(fee, maxFee));

        uint256 nativeFee = 0;
        if (payInGho) {
            if (payer != address(this)) {
                IERC20(GHO_TOKEN).safeTransferFrom(payer, address(this), fee);
            }
            IERC20(GHO_TOKEN).safeIncreaseAllowance(CCIP_ROUTER, fee);
        } else {
            nativeFee = fee;
        }

        return
            IRouterClient(CCIP_ROUTER).ccipSend{value: nativeFee}(
                destChainSelector,
                message
            );
    }
}
