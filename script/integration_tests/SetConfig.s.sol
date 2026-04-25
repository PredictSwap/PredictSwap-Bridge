// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

contract SetConfig is Script {
    uint32 constant EXECUTOR_CONFIG_TYPE = 1;
    uint32 constant ULN_CONFIG_TYPE = 2;

    uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function SetLibrariesBSC() external {
        address _endpoint = vm.envAddress("BSC_LZ_ENDPOINT");
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(_endpoint);

        address oapp = vm.envAddress("PREDICTION_MARKET_ESCROW_ADDRESS");
        address sendLib = vm.envAddress("BSC_SEND_LIB");
        address receiveLib = vm.envAddress("BSC_RECEIVE_LIB");
        // address dvn         = vm.envAddress("BSC_DVN");
        address dvn1 = vm.envAddress("BSC_DVN_1");
        address dvn2 = vm.envAddress("BSC_DVN_2");
        address executor = vm.envAddress("BSC_EXECUTOR");
        uint32 dstEid = uint32(vm.envUint("POLYGON_EID"));

        // address[] memory requiredDVNs = new address[](1);
        // requiredDVNs[0] = dvn;

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = dvn1;
        requiredDVNs[1] = dvn2;

        UlnConfig memory uln = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        ExecutorConfig memory exec = ExecutorConfig({maxMessageSize: 10000, executor: executor});

        // send config: ULN + executor
        SetConfigParam[] memory sendParams = new SetConfigParam[](2);
        sendParams[0] = SetConfigParam(dstEid, EXECUTOR_CONFIG_TYPE, abi.encode(exec));
        sendParams[1] = SetConfigParam(dstEid, ULN_CONFIG_TYPE, abi.encode(uln));

        // receive config: ULN only
        SetConfigParam[] memory receiveParams = new SetConfigParam[](1);
        receiveParams[0] = SetConfigParam(dstEid, ULN_CONFIG_TYPE, abi.encode(uln));

        vm.startBroadcast(deployerKey);
        endpoint.setSendLibrary(oapp, dstEid, sendLib);
        endpoint.setReceiveLibrary(oapp, dstEid, receiveLib, 0);
        endpoint.setConfig(oapp, sendLib, sendParams);
        endpoint.setConfig(oapp, receiveLib, receiveParams);
        vm.stopBroadcast();

        console.log("BSC send + receive configured");
        console.log("  SendLib:", sendLib);
        console.log("  ReceiveLib:", receiveLib);
        // console.log("  DVN:", dvn);
        console.log("  DVN 1:", dvn1);
        console.log("  DVN 2:", dvn2);
        console.log("  Executor:", executor);
    }

    function SetLibrariesPolygon() external {
        address _endpoint = vm.envAddress("POLYGON_LZ_ENDPOINT");
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(_endpoint);

        address oapp = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address sendLib = vm.envAddress("POLYGON_SEND_LIB");
        address receiveLib = vm.envAddress("POLYGON_RECEIVE_LIB");
        // address dvn         = vm.envAddress("POLYGON_DVN");
        address dvn1 = vm.envAddress("POLYGON_DVN_1");
        address dvn2 = vm.envAddress("POLYGON_DVN_2");
        address executor = vm.envAddress("POLYGON_EXECUTOR");
        uint32 dstEid = uint32(vm.envUint("BSC_EID"));

        // address[] memory requiredDVNs = new address[](1);
        // requiredDVNs[0] = dvn;

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = dvn1;
        requiredDVNs[1] = dvn2;

        UlnConfig memory uln = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        ExecutorConfig memory exec = ExecutorConfig({maxMessageSize: 10000, executor: executor});

        // send config: ULN + executor
        SetConfigParam[] memory sendParams = new SetConfigParam[](2);
        sendParams[0] = SetConfigParam(dstEid, EXECUTOR_CONFIG_TYPE, abi.encode(exec));
        sendParams[1] = SetConfigParam(dstEid, ULN_CONFIG_TYPE, abi.encode(uln));

        // receive config: ULN only
        SetConfigParam[] memory receiveParams = new SetConfigParam[](1);
        receiveParams[0] = SetConfigParam(dstEid, ULN_CONFIG_TYPE, abi.encode(uln));

        vm.startBroadcast(deployerKey);
        endpoint.setSendLibrary(oapp, dstEid, sendLib);
        endpoint.setReceiveLibrary(oapp, dstEid, receiveLib, 0);
        endpoint.setConfig(oapp, sendLib, sendParams);
        endpoint.setConfig(oapp, receiveLib, receiveParams);
        vm.stopBroadcast();

        console.log("Polygon send + receive configured");
        console.log("  SendLib:", sendLib);
        console.log("  ReceiveLib:", receiveLib);
        // console.log("  DVN:", dvn);
        console.log("  DVN 1:", dvn1);
        console.log("  DVN 2:", dvn2);
        console.log("  Executor:", executor);
    }
}
