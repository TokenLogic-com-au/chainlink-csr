// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title FeeCodec Library.
 * @dev A library for encoding and decoding fee-related data.
 */
library FeeCodec {
    /**
     * @dev Error thrown when the length of the packed data is invalid.
     * @param length The actual length of the provided data.
     * @param expectedLength The length that was expected (minimum or exact, depending on the caller).
     */
    error FeeCodecInvalidDataLength(uint256 length, uint256 expectedLength);

    /**
     * @dev Packs `recipient`, `amount`, and `feeData` into a single bytes array.
     * The layout is: 20 bytes `recipient`, 32 bytes `amount`, followed by the raw `feeData` bytes.
     * @param recipient The address that will receive the tokens on the destination chain.
     * @param amount The amount of tokens to be sent.
     * @param feeData The encoded fee data used by the bridge.
     * @return The packed bytes array.
     */
    function encodePackedData(
        address recipient,
        uint256 amount,
        bytes calldata feeData
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(recipient, amount, feeData);
    }

    /**
     * @dev Memory variant of {encodePackedData}. Packs `recipient`, `amount`, and `feeData`
     * into a single bytes array with layout: 20 bytes `recipient`, 32 bytes `amount`, then the raw `feeData`.
     * @param recipient The address that will receive the tokens on the destination chain.
     * @param amount The amount of tokens to be sent.
     * @param feeData The encoded fee data used by the bridge.
     * @return The packed bytes array.
     */
    function encodePackedDataMemory(
        address recipient,
        uint256 amount,
        bytes memory feeData
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(recipient, amount, feeData);
    }

    /**
     * @dev Unpacks `packedData` produced by {encodePackedData} into its components.
     * Reads 20 bytes for `recipient`, the next 32 bytes for `amount`, and treats the remaining bytes as `feeData`.
     *
     * Requirements:
     *
     * - `packedData` must have a length of at least 52 bytes.
     *
     * @param packedData The packed bytes array to decode.
     * @return recipient The address that will receive the tokens on the destination chain.
     * @return amount The amount of tokens to be sent.
     * @return feeData The encoded fee data used by the bridge.
     */
    function decodePackedData(
        bytes calldata packedData
    )
        internal
        pure
        returns (address recipient, uint256 amount, bytes calldata feeData)
    {
        if (packedData.length < 52)
            revert FeeCodecInvalidDataLength(packedData.length, 52);

        recipient = address(uint160(bytes20(packedData[0:20])));
        amount = uint256(bytes32(packedData[20:52]));
        feeData = packedData[52:];
    }

    /**
     * @dev Memory variant of {decodePackedData}. Unpacks `packedData` into its components,
     * reading 20 bytes for `recipient`, 32 bytes for `amount`, and the remaining bytes as `feeData`.
     *
     * Requirements:
     *
     * - `packedData` must have a length of at least 52 bytes.
     *
     * @param packedData The packed bytes array to decode.
     * @return recipient The address that will receive the tokens on the destination chain.
     * @return amount The amount of tokens to be sent.
     * @return feeData The encoded fee data used by the bridge.
     */
    function decodePackedDataMemory(
        bytes memory packedData
    )
        internal
        pure
        returns (address recipient, uint256 amount, bytes memory feeData)
    {
        uint256 length = packedData.length;

        if (length < 52)
            revert FeeCodecInvalidDataLength(packedData.length, 52);

        feeData = abi.encodePacked(packedData); // Force solidity to copy the data

        assembly {
            recipient := shr(96, mload(add(packedData, 0x20)))
            amount := mload(add(packedData, 0x34))

            feeData := add(packedData, 0x34)
            mstore(feeData, sub(length, 0x34))
        }
    }

    /**
     * @dev Decodes the common fee header from `feeData`, reading 16 bytes for `feeAmount`
     * followed by 1 byte for the `payInLink` flag.
     *
     * Requirements:
     *
     * - `feeData` must have a length of at least 17 bytes.
     *
     * @param feeData The encoded fee data to decode.
     * @return feeAmount The fee amount for the transfer.
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     */
    function decodeFee(
        bytes calldata feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink) {
        if (feeData.length < 17)
            revert FeeCodecInvalidDataLength(feeData.length, 17);
        return (uint128(bytes16(feeData[0:16])), feeData[16] != 0);
    }

    /**
     * @dev Memory variant of {decodeFee}. Decodes the common fee header from `feeData`,
     * reading 16 bytes for `feeAmount` followed by 1 byte for the `payInLink` flag.
     *
     * Requirements:
     *
     * - `feeData` must have a length of at least 17 bytes.
     *
     * @param feeData The encoded fee data to decode.
     * @return feeAmount The fee amount for the transfer.
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     */
    function decodeFeeMemory(
        bytes memory feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink) {
        if (feeData.length < 17)
            revert FeeCodecInvalidDataLength(feeData.length, 17);
        bytes32 value = bytes32(feeData);

        feeAmount = uint128(bytes16(value));
        payInLink = (uint256(value) >> 120) & 0xff != 0;
    }

    /**
     * @dev Encodes the fee data for a Cross-Chain Interoperability Protocol (CCIP) transfer.
     * The layout is: 16 bytes `maxFee`, 1 byte `payInLink`, 4 bytes `gasLimit` (21 bytes total).
     * @param maxFee The maximum fee that the sender is willing to pay.
     * @param payInLink Whether the fee should be paid in LINK tokens (true) or in the native token of the source chain (false).
     * @param gasLimit The minimum amount of gas that should be used to execute the transaction on the destination chain.
     * @return The encoded CCIP fee data.
     */
    function encodeCCIP(
        uint128 maxFee,
        bool payInLink,
        uint32 gasLimit
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(maxFee, payInLink, gasLimit);
    }

    /**
     * @dev Decodes the fee data for a Cross-Chain Interoperability Protocol (CCIP) transfer.
     * Reads 16 bytes for `maxFee`, 1 byte for `payInLink`, and 4 bytes for `gasLimit`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 21 bytes.
     *
     * @param feeData The encoded CCIP fee data to decode.
     * @return maxFee The maximum fee that the sender is willing to pay.
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token of the source chain (false).
     * @return gasLimit The minimum amount of gas that should be used to execute the transaction on the destination chain.
     */
    function decodeCCIP(
        bytes calldata feeData
    ) internal pure returns (uint128 maxFee, bool payInLink, uint32 gasLimit) {
        if (feeData.length != 21)
            revert FeeCodecInvalidDataLength(feeData.length, 21);
        maxFee = uint128(bytes16(feeData[0:16]));
        payInLink = feeData[16] != 0;
        gasLimit = uint32(bytes4(feeData[17:21]));
    }

    /**
     * @dev Memory variant of {decodeCCIP}. Decodes the fee data for a CCIP transfer,
     * reading 16 bytes for `maxFee`, 1 byte for `payInLink`, and 4 bytes for `gasLimit`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of at least 21 bytes.
     *
     * @param feeData The encoded CCIP fee data to decode.
     * @return maxFee The maximum fee that the sender is willing to pay.
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token of the source chain (false).
     * @return gasLimit The minimum amount of gas that should be used to execute the transaction on the destination chain.
     */
    function decodeCCIPMemory(
        bytes memory feeData
    ) internal pure returns (uint128 maxFee, bool payInLink, uint32 gasLimit) {
        if (feeData.length < 21)
            revert FeeCodecInvalidDataLength(feeData.length, 21);
        bytes32 value = bytes32(feeData);

        maxFee = uint128(bytes16(value));
        payInLink = uint8(uint256(value) >> 120) != 0;
        gasLimit = uint32(uint256(value) >> 88);
    }

    /**
     * @dev Encodes the fee data for an Arbitrum L1-to-L2 transfer.
     * The total fee amount is computed as `maxSubmissionCost` + `gasPriceBid` * `maxGas`.
     * The layout is: 16 bytes total `feeAmount`, 1 byte `payInLink` (always 0), 4 bytes `maxGas`, 8 bytes `gasPriceBid` (29 bytes total).
     * @param maxSubmissionCost The base submission cost for the L2 retryable ticket.
     * @param maxGas The maximum amount of gas for the L2 retryable ticket.
     * @param gasPriceBid The gas price bid for the L2 retryable ticket.
     * @return The encoded Arbitrum L1-to-L2 fee data.
     */
    function encodeArbitrumL1toL2(
        uint128 maxSubmissionCost,
        uint32 maxGas,
        uint64 gasPriceBid
    ) internal pure returns (bytes memory) {
        uint128 feeAmount = maxSubmissionCost + uint128(gasPriceBid) * maxGas;
        return abi.encodePacked(feeAmount, uint8(0), maxGas, gasPriceBid);
    }

    /**
     * @dev Decodes the fee data for an Arbitrum L1-to-L2 transfer.
     * Reads 16 bytes for `feeAmount`, 1 byte for `payInLink`, 4 bytes for `maxGas`, and 8 bytes for `gasPriceBid`,
     * then derives `maxSubmissionCost` as `feeAmount` - `gasPriceBid` * `maxGas`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 29 bytes.
     *
     * @param feeData The encoded Arbitrum L1-to-L2 fee data to decode.
     * @return feeAmount The total fee amount for the transfer (`maxSubmissionCost` + `gasPriceBid` * `maxGas`).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     * @return maxSubmissionCost The base submission cost for the L2 retryable ticket.
     * @return maxGas The maximum amount of gas for the L2 retryable ticket.
     * @return gasPriceBid The gas price bid for the L2 retryable ticket.
     */
    function decodeArbitrumL1toL2(
        bytes calldata feeData
    )
        internal
        pure
        returns (
            uint128 feeAmount,
            bool payInLink,
            uint128 maxSubmissionCost,
            uint32 maxGas,
            uint64 gasPriceBid
        )
    {
        if (feeData.length != 29)
            revert FeeCodecInvalidDataLength(feeData.length, 29);
        feeAmount = uint128(bytes16(feeData[0:16]));
        payInLink = feeData[16] != 0;
        maxGas = uint32(bytes4(feeData[17:21]));
        gasPriceBid = uint64(bytes8(feeData[21:29]));

        maxSubmissionCost = feeAmount - uint128(gasPriceBid) * maxGas;
    }

    /**
     * @dev Memory variant of {decodeArbitrumL1toL2}. Decodes the fee data for an Arbitrum L1-to-L2 transfer,
     * reading 16 bytes for `feeAmount`, 1 byte for `payInLink`, 4 bytes for `maxGas`, and 8 bytes for `gasPriceBid`,
     * then derives `maxSubmissionCost` as `feeAmount` - `gasPriceBid` * `maxGas`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 29 bytes.
     *
     * @param feeData The encoded Arbitrum L1-to-L2 fee data to decode.
     * @return feeAmount The total fee amount for the transfer (`maxSubmissionCost` + `gasPriceBid` * `maxGas`).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     * @return maxSubmissionCost The base submission cost for the L2 retryable ticket.
     * @return maxGas The maximum amount of gas for the L2 retryable ticket.
     * @return gasPriceBid The gas price bid for the L2 retryable ticket.
     */
    function decodeArbitrumL1toL2Memory(
        bytes memory feeData
    )
        internal
        pure
        returns (
            uint128 feeAmount,
            bool payInLink,
            uint128 maxSubmissionCost,
            uint32 maxGas,
            uint64 gasPriceBid
        )
    {
        if (feeData.length != 29)
            revert FeeCodecInvalidDataLength(feeData.length, 29);
        bytes32 value = bytes32(feeData);

        feeAmount = uint128(bytes16(value));
        payInLink = uint8(uint256(value) >> 120) != 0;
        maxGas = uint32(uint256(value) >> 88);
        gasPriceBid = uint64(uint256(value) >> 24);

        maxSubmissionCost = feeAmount - uint128(gasPriceBid) * maxGas;
    }

    /**
     * @dev Encodes the fee data for an Optimism L1-to-L2 transfer.
     * The layout is: 17 bytes of zero (16 bytes `feeAmount` always zero, 1 byte `payInLink` always 0)
     * followed by 4 bytes `l2Gas` (21 bytes total).
     * @param l2Gas The minimum amount of gas that should be used for the deposit message on L2.
     * @return The encoded Optimism L1-to-L2 fee data.
     */
    function encodeOptimismL1toL2(
        uint32 l2Gas
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint136(0), l2Gas);
    }

    /**
     * @dev Decodes the fee data for an Optimism L1-to-L2 transfer.
     * Reads 16 bytes for `feeAmount`, 1 byte for `payInLink`, and 4 bytes for `l2Gas`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 21 bytes.
     *
     * @param feeData The encoded Optimism L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer (always zero for an Optimism L1-to-L2 transfer).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     * @return l2Gas The minimum amount of gas that should be used for the deposit message on L2.
     */
    function decodeOptimismL1toL2(
        bytes calldata feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink, uint32 l2Gas) {
        if (feeData.length != 21)
            revert FeeCodecInvalidDataLength(feeData.length, 21);
        feeAmount = uint128(bytes16(feeData[0:16]));
        payInLink = feeData[16] != 0;
        l2Gas = uint32(bytes4(feeData[17:21]));
    }

    /**
     * @dev Memory variant of {decodeOptimismL1toL2}. Decodes the fee data for an Optimism L1-to-L2 transfer,
     * reading 16 bytes for `feeAmount`, 1 byte for `payInLink`, and 4 bytes for `l2Gas`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 21 bytes.
     *
     * @param feeData The encoded Optimism L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer (always zero for an Optimism L1-to-L2 transfer).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     * @return l2Gas The minimum amount of gas that should be used for the deposit message on L2.
     */
    function decodeOptimismL1toL2Memory(
        bytes memory feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink, uint32 l2Gas) {
        if (feeData.length != 21)
            revert FeeCodecInvalidDataLength(feeData.length, 21);
        bytes32 value = bytes32(feeData);

        feeAmount = uint128(bytes16(value));
        payInLink = uint8(uint256(value) >> 120) != 0;
        l2Gas = uint32(uint256(value) >> 88);
    }

    /**
     * @dev Encodes the fee data for a Base L1-to-L2 transfer.
     * The layout is: 17 bytes of zero (16 bytes `feeAmount` always zero, 1 byte `payInLink` always 0)
     * followed by 4 bytes `l2Gas` (21 bytes total).
     * @param l2Gas The minimum amount of gas that should be used for the deposit message on L2.
     * @return The encoded Base L1-to-L2 fee data.
     */
    function encodeBaseL1toL2(
        uint32 l2Gas
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint136(0), l2Gas);
    }

    /**
     * @dev Decodes the fee data for a Base L1-to-L2 transfer.
     * Reads 16 bytes for `feeAmount`, 1 byte for `payInLink`, and 4 bytes for `l2Gas`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 21 bytes.
     *
     * @param feeData The encoded Base L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer (always zero for a Base L1-to-L2 transfer).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     * @return l2Gas The minimum amount of gas that should be used for the deposit message on L2.
     */
    function decodeBaseL1toL2(
        bytes calldata feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink, uint32 l2Gas) {
        if (feeData.length != 21)
            revert FeeCodecInvalidDataLength(feeData.length, 21);
        feeAmount = uint128(bytes16(feeData[0:16]));
        payInLink = feeData[16] != 0;
        l2Gas = uint32(bytes4(feeData[17:21]));
    }

    /**
     * @dev Memory variant of {decodeBaseL1toL2}. Decodes the fee data for a Base L1-to-L2 transfer,
     * reading 16 bytes for `feeAmount`, 1 byte for `payInLink`, and 4 bytes for `l2Gas`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 21 bytes.
     *
     * @param feeData The encoded Base L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer (always zero for a Base L1-to-L2 transfer).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     * @return l2Gas The minimum amount of gas that should be used for the deposit message on L2.
     */
    function decodeBaseL1toL2Memory(
        bytes memory feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink, uint32 l2Gas) {
        if (feeData.length != 21)
            revert FeeCodecInvalidDataLength(feeData.length, 21);
        bytes32 value = bytes32(feeData);

        feeAmount = uint128(bytes16(value));
        payInLink = uint8(uint256(value) >> 120) != 0;
        l2Gas = uint32(uint256(value) >> 88);
    }

    /**
     * @dev Encodes the fee data for a Frax Ferry L1-to-L2 transfer.
     * The layout is 17 bytes of zero (16 bytes `feeAmount` always zero, 1 byte `payInLink` always 0).
     * @return The encoded Frax Ferry L1-to-L2 fee data.
     */
    function encodeFraxFerryL1toL2() internal pure returns (bytes memory) {
        return abi.encodePacked(uint136(0));
    }

    /**
     * @dev Decodes the fee data for a Frax Ferry L1-to-L2 transfer.
     * Reads 16 bytes for `feeAmount` and 1 byte for `payInLink`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 17 bytes.
     *
     * @param feeData The encoded Frax Ferry L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer (always zero for a Frax Ferry L1-to-L2 transfer).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     */
    function decodeFraxFerryL1toL2(
        bytes calldata feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink) {
        if (feeData.length != 17)
            revert FeeCodecInvalidDataLength(feeData.length, 17);
        feeAmount = uint128(bytes16(feeData[0:16]));
        payInLink = feeData[16] != 0;
    }

    /**
     * @dev Memory variant of {decodeFraxFerryL1toL2}. Decodes the fee data for a Frax Ferry L1-to-L2 transfer,
     * reading 16 bytes for `feeAmount` and 1 byte for `payInLink`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 17 bytes.
     *
     * @param feeData The encoded Frax Ferry L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer (always zero for a Frax Ferry L1-to-L2 transfer).
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     */
    function decodeFraxFerryL1toL2Memory(
        bytes memory feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink) {
        if (feeData.length != 17)
            revert FeeCodecInvalidDataLength(feeData.length, 17);
        bytes32 value = bytes32(feeData);

        feeAmount = uint128(bytes16(value));
        payInLink = uint8(uint256(value) >> 120) != 0;
    }

    /**
     * @dev Encodes the fee data for a Linea L1-to-L2 transfer.
     * The layout is 17 bytes of zero (16 bytes `feeAmount` always zero, 1 byte `payInLink` always 0).
     * @return The encoded Linea L1-to-L2 fee data.
     */
    function encodeLineaL1toL2() internal pure returns (bytes memory) {
        return abi.encodePacked(uint136(0));
    }

    /**
     * @dev Decodes the fee data for a Linea L1-to-L2 transfer.
     * Reads 16 bytes for `feeAmount` and 1 byte for `payInLink`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 17 bytes.
     *
     * @param feeData The encoded Linea L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer.
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     */
    function decodeLineaL1toL2(
        bytes calldata feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink) {
        if (feeData.length != 17)
            revert FeeCodecInvalidDataLength(feeData.length, 17);
        feeAmount = uint128(bytes16(feeData[0:16]));
        payInLink = feeData[16] != 0;
    }

    /**
     * @dev Memory variant of {decodeLineaL1toL2}. Decodes the fee data for a Linea L1-to-L2 transfer,
     * reading 16 bytes for `feeAmount` and 1 byte for `payInLink`.
     *
     * Requirements:
     *
     * - `feeData` must have a length of 17 bytes.
     *
     * @param feeData The encoded Linea L1-to-L2 fee data to decode.
     * @return feeAmount The fee amount for the transfer.
     * @return payInLink Whether the fee should be paid in LINK tokens (true) or in the native token (false).
     */
    function decodeLineaL1toL2Memory(
        bytes memory feeData
    ) internal pure returns (uint128 feeAmount, bool payInLink) {
        if (feeData.length != 17)
            revert FeeCodecInvalidDataLength(feeData.length, 17);
        bytes32 value = bytes32(feeData);

        feeAmount = uint128(bytes16(value));
        payInLink = uint8(uint256(value) >> 120) != 0;
    }
}
