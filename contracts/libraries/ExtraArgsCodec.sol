// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title ExtraArgsCodec Library
 * @dev Type definitions and codec for the CCIP `GenericExtraArgsV3` extra-args blob.
 * The blob is a compactly encoded {GenericExtraArgsV3} struct prefixed with {GENERIC_EXTRA_ARGS_V3_TAG}: fixed-width
 * header fields followed by length-prefixed variable-width fields, in the order given by
 * {GENERIC_EXTRA_ARGS_V3_BASE_SIZE}. When a sender supplies one, `CCIPSenderUpgradeable` decodes it to enforce the
 * `minProcessMessageGas` floor on the embedded `gasLimit` and to validate `requestedFinalityConfig`, then forwards
 * the blob to the CCIP router unmodified; every other field is passed through without inspection. When no blob is
 * supplied, the router receives an `EVMExtraArgsV1` built from the `gasLimit` encoded in the fee data instead.
 *
 * The struct mirrors Chainlink's own definition; see the CCIP documentation for the authoritative reference.
 */
library ExtraArgsCodec {
    /// @notice The blob ended before a field it declares could be read, or trailing bytes were left unconsumed.
    /// @param location The decoding step that detected the mismatch.
    /// @param offset The offset the decoder had reached, or the blob length when the header itself is too short.
    error InvalidDataLength(EncodingErrorLocation location, uint256 offset);
    /// @notice The leading 4 bytes of the blob are not {GENERIC_EXTRA_ARGS_V3_TAG}.
    /// @param expected The only accepted tag.
    /// @param actual The tag actually found at the start of the blob.
    error InvalidExtraArgsTag(bytes4 expected, bytes4 actual);
    /// @notice A length-prefixed address field declares a length other than 0 or 20.
    /// @param length The rejected declared length.
    error InvalidAddressLength(uint256 length);

    /// @dev Ordinals must stay aligned with Chainlink's upstream `EncodingErrorLocation` so revert data decodes
    /// identically; only the trailing members unused by this vendored decoder are omitted.
    enum EncodingErrorLocation {
        DECODE_FIELD_LENGTH,
        DECODE_FIELD_CONTENT,
        EXTRA_ARGS_STATIC_LENGTH_FIELDS,
        EXTRA_ARGS_FINAL_OFFSET
    }

    /// @dev The 4-byte tag that prefixes an ABI-encoded {GenericExtraArgsV3} blob. It is the only extra-args
    /// version accepted: a non-empty blob carrying any other tag reverts with `InvalidExtraArgsTag`.
    bytes4 public constant GENERIC_EXTRA_ARGS_V3_TAG = 0xa69dd4aa;

    // Base size excludes all variable-length fields (CCV addresses/args, executor address, executorArgs, tokenReceiver,
    // tokenArgs).
    // Encoding order: tag(4) + gasLimit(4) + requestedFinalityConfig(4) + ccvsLength(1) + executorLength(1) +
    // executorArgsLength(2) + tokenReceiverLength(1) + tokenArgsLength(2) = 19 bytes.
    uint256 public constant GENERIC_EXTRA_ARGS_V3_BASE_SIZE =
        4 + 4 + 4 + 1 + 1 + 2 + 1 + 2;

    // Size of the fixed-position header: tag(4) + gasLimit(4) + requestedFinalityConfig(4) + ccvsLength(1).
    uint256 public constant GENERIC_EXTRA_ARGS_V3_STATIC_LENGTH_SIZE =
        4 + 4 + 4 + 1;

    /// @dev The V3 extra-args payload accepted by the CCIP router.
    struct GenericExtraArgsV3 {
        /// @notice Gas limit for the callback on the destination chain. If the gas limit is zero and the message data
        /// length is also zero, no callback will be performed, even if a receiver is specified. A gas limit of zero is
        /// useful when only token transfers are desired, or when the receiver is an EOA account instead of a contract.
        /// Besides this gasLimit check, there are other checks on the destination chain that may prevent the callback from
        /// being executed, depending on the destination chain family.
        /// @dev The sender is billed for the gas specified, not the gas actually used. Any unspent gas is not refunded.
        /// There are various ways to estimate the gas required for a callback on the destination chain, depending on the
        /// chain family. Please refer to the documentation for each chain for more details.
        uint32 gasLimit;
        /// @notice The finality config, see FinalityCodec for encoding details.
        /// @dev May be zero to indicate waiting for finality is desired.
        bytes4 requestedFinalityConfig;
        /// @notice An array of CCV addresses representing the cross-chain verifiers to be used for the message.
        /// @dev May be empty to specify the default verifier(s) should be used.
        address[] ccvs;
        /// @notice Optional arguments that are passed into the CCV without modification or inspection. CCIP itself does not
        /// interpret these arguments: they are encoded in whatever format the CCV has decided.
        /// @dev Must be the same length as the `ccvs` array. May have empty bytes as arguments.
        bytes[] ccvArgs;
        /// @notice Address of the executor contract on the source chain. The executor is responsible for executing the
        /// message on the destination chains once a quorum of CCVs have verified the message.
        /// @dev May be address(0) to indicate the default executor should be used.
        address executor;
        /// @notice Destination chain family specific arguments for the executor. This field is passed to the destination
        /// chain as part of the message itself and these args are therefore fully protected through the message ID. The
        /// format of this field is specific to each chain family and is not interpreted by CCIP itself, only by the
        /// executor. Things that may be included here are Solana accounts or Sui object IDs, which must be secured through
        /// the message ID as passing in incorrect values can lead to loss of funds.
        /// @dev May be empty depending on the destination chain.
        bytes executorArgs;
        /// @notice Address of the token receiver on the destination chain, in bytes format. If an empty bytes array is
        /// provided, the receiver address from the message itself is used for token transfers. This field allows for
        /// scenarios where the token receiver is different from the message receiver.
        /// @dev May be empty, the behavior differs depending on if there is a token transfer or not:
        /// - If there is a token transfer, the receiver from the message is used.
        /// - If there is no token transfer, this field should be empty.
        bytes tokenReceiver;
        /// @notice Additional arguments for token transfers. This field is passed into the token pool on the source chain
        /// and is not inspected by CCIP itself. The format of this field is therefore specific to the token pool being used
        /// and may vary between different pools.
        /// @dev May be empty depending on the token pool.
        bytes tokenArgs;
    }

    /// @notice Builds the minimal V3 blob: a gas limit and finality config with no CCVs, executor, or token fields.
    /// @param gasLimit Gas limit for the callback on the destination chain.
    /// @param finalityConfig The requested finality config, see {FinalityCodec}.
    /// @return The encoded {GenericExtraArgsV3} blob.
    function _getBasicEncodedExtraArgsV3(
        uint32 gasLimit,
        bytes4 finalityConfig
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                GENERIC_EXTRA_ARGS_V3_TAG,
                gasLimit,
                finalityConfig,
                bytes7(0)
            );
    }

    /// @notice Decodes bytes into a GenericExtraArgsV3 struct using assembly for gas efficiency.
    /// @param encoded The encoded bytes to decode.
    /// @return extraArgs The decoded GenericExtraArgsV3 struct.
    function _decodeGenericExtraArgsV3(
        bytes calldata encoded
    ) internal pure returns (GenericExtraArgsV3 memory extraArgs) {
        // Check if encodedLength is at least the minimum size.
        if (encoded.length < GENERIC_EXTRA_ARGS_V3_BASE_SIZE) {
            revert InvalidDataLength(
                EncodingErrorLocation.EXTRA_ARGS_STATIC_LENGTH_FIELDS,
                encoded.length
            );
        }

        // Check tag.
        bytes4 tag;
        assembly ("memory-safe") {
            tag := calldataload(encoded.offset)
        }

        if (tag != GENERIC_EXTRA_ARGS_V3_TAG) {
            revert InvalidExtraArgsTag(GENERIC_EXTRA_ARGS_V3_TAG, tag);
        }

        uint256 ccvsLength;
        // Read static-length fields.
        assembly ("memory-safe") {
            // Read gas limit (4 bytes).
            let gasLimit := calldataload(add(encoded.offset, 4))
            mstore(extraArgs, and(shr(224, gasLimit), 0xFFFFFFFF))

            // Read requestedFinalityConfig (4 bytes).
            // bytes4 is left-aligned in memory, so mask the top 4 bytes of the loaded word directly
            // instead of shifting right (which would produce a right-aligned uint that reads back as zero).
            let finalityWord := calldataload(add(encoded.offset, 8))
            mstore(add(extraArgs, 32), and(finalityWord, shl(224, 0xFFFFFFFF)))

            // Read ccvs length (1 byte).
            ccvsLength := byte(0, calldataload(add(encoded.offset, 12)))
        }

        uint256 offset = GENERIC_EXTRA_ARGS_V3_STATIC_LENGTH_SIZE; // Skip tag, gasLimit, requestedFinalityConfig, ccvsLength.

        // Allocate arrays for CCVs.
        extraArgs.ccvs = new address[](ccvsLength);
        extraArgs.ccvArgs = new bytes[](ccvsLength);

        // Decode CCVs and args.
        for (uint256 i = 0; i < ccvsLength; ++i) {
            (extraArgs.ccvs[i], offset) = _readUint8PrefixedAddress(
                encoded,
                offset
            );
            (extraArgs.ccvArgs[i], offset) = _readUint16PrefixedBytes(
                encoded,
                offset
            );
        }

        // Read executor, executorArgs, tokenReceiver, and tokenArgs.
        (extraArgs.executor, offset) = _readUint8PrefixedAddress(
            encoded,
            offset
        );
        (extraArgs.executorArgs, offset) = _readUint16PrefixedBytes(
            encoded,
            offset
        );
        (extraArgs.tokenReceiver, offset) = _readUint8PrefixedBytes(
            encoded,
            offset
        );
        (extraArgs.tokenArgs, offset) = _readUint16PrefixedBytes(
            encoded,
            offset
        );

        // Ensure we've consumed all bytes.
        if (offset != encoded.length)
            revert InvalidDataLength(
                EncodingErrorLocation.EXTRA_ARGS_FINAL_OFFSET,
                offset
            );

        return extraArgs;
    }

    /// @notice Reads a `uint8`-length-prefixed address field. A declared length of zero yields `address(0)`.
    /// @param encoded The encoded blob being decoded.
    /// @param offset The offset of the length prefix.
    /// @return addr The decoded address.
    /// @return newOffset The offset just past the field.
    function _readUint8PrefixedAddress(
        bytes calldata encoded,
        uint256 offset
    ) private pure returns (address addr, uint256 newOffset) {
        unchecked {
            if (offset + 1 > encoded.length)
                revert InvalidDataLength(
                    EncodingErrorLocation.DECODE_FIELD_LENGTH,
                    offset
                );
            uint256 addrLength;
            assembly ("memory-safe") {
                addrLength := byte(0, calldataload(add(encoded.offset, offset)))
            }
            newOffset = offset + 1;

            if (addrLength == 0) {
                return (address(0), newOffset);
            }

            if (addrLength != 20) {
                revert InvalidAddressLength(addrLength);
            }

            if (newOffset + addrLength > encoded.length) {
                revert InvalidDataLength(
                    EncodingErrorLocation.DECODE_FIELD_CONTENT,
                    newOffset
                );
            }

            assembly ("memory-safe") {
                let addrData := calldataload(add(encoded.offset, newOffset))
                addr := shr(96, addrData)
            }
            newOffset += addrLength;
        }
        return (addr, newOffset);
    }

    /// @notice Reads a `uint16`-length-prefixed bytes field.
    /// @param encoded The encoded blob being decoded.
    /// @param offset The offset of the length prefix.
    /// @return data The decoded field, as a slice of `encoded`.
    /// @return newOffset The offset just past the field.
    function _readUint16PrefixedBytes(
        bytes calldata encoded,
        uint256 offset
    ) private pure returns (bytes calldata data, uint256 newOffset) {
        unchecked {
            if (offset + 2 > encoded.length)
                revert InvalidDataLength(
                    EncodingErrorLocation.DECODE_FIELD_LENGTH,
                    offset
                );
            uint256 dataLength;
            assembly ("memory-safe") {
                let lengthData := calldataload(add(encoded.offset, offset))
                dataLength := and(shr(240, lengthData), 0xFFFF)
            }
            newOffset = offset + 2;

            if (newOffset + dataLength > encoded.length) {
                revert InvalidDataLength(
                    EncodingErrorLocation.DECODE_FIELD_CONTENT,
                    newOffset
                );
            }

            data = encoded[newOffset:newOffset + dataLength];
            newOffset += dataLength;
        }
        return (data, newOffset);
    }

    /// @notice Reads a `uint8`-length-prefixed bytes field.
    /// @param encoded The encoded blob being decoded.
    /// @param offset The offset of the length prefix.
    /// @return data The decoded field, as a slice of `encoded`.
    /// @return newOffset The offset just past the field.
    function _readUint8PrefixedBytes(
        bytes calldata encoded,
        uint256 offset
    ) private pure returns (bytes calldata data, uint256 newOffset) {
        unchecked {
            if (offset + 1 > encoded.length)
                revert InvalidDataLength(
                    EncodingErrorLocation.DECODE_FIELD_LENGTH,
                    offset
                );
            uint256 dataLength;
            assembly ("memory-safe") {
                dataLength := byte(0, calldataload(add(encoded.offset, offset)))
            }
            newOffset = offset + 1;

            if (newOffset + dataLength > encoded.length) {
                revert InvalidDataLength(
                    EncodingErrorLocation.DECODE_FIELD_CONTENT,
                    newOffset
                );
            }

            data = encoded[newOffset:newOffset + dataLength];
            newOffset += dataLength;
        }
        return (data, newOffset);
    }
}
