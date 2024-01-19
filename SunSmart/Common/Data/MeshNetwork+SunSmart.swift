//
//  MeshNetwork+SunSmart.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/18.
//

import Foundation
import NordicSigMeshSDK

public enum DataError: Error {
    /// 空间已超出最大范围
    case exceededMaxSpaces
    
    
}

let testMeshJsonDataString = "{\"$schema\":\"http://json-schema.org/draft-04/schema#\",\"appKeys\":[{\"boundNetKey\":0,\"index\":0,\"key\":\"CC9B14BE6945AB43B8FA0FB577C70D41\",\"name\":\"ApplicationKey0\"}],\"groups\":[],\"id\":\"https://www.bluetooth.com/specifications/specs/mesh-cdb-1-0-1-schema.json#\",\"meshName\":\"Space 1\",\"meshUUID\":\"9F47E905-486E-42EF-907E-883D67504C8A\",\"netKeys\":[{\"index\":0,\"key\":\"4D062F216050A8CB8F116B2734384708\",\"minSecurity\":\"insecure\",\"name\":\"Primary Network Key\",\"phase\":0,\"timestamp\":\"2024-01-09T06:49:33Z\"}],\"nodes\":[{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"004C\",\"configComplete\":true,\"crpl\":\"7FFF\",\"deviceKey\":\"6DEA93421B7B4673816F5D2E68503370\",\"elements\":[{\"index\":0,\"location\":\"0001\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0001\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"000B\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"000F\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0005\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1205\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1102\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1008\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1005\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1001\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1003\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1303\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1306\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1302\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1305\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1309\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1200\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1206\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1207\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1310\",\"subscribe\":[]}],\"name\":\"Primary Element\"},{\"index\":1,\"location\":\"0002\",\"models\":[{\"bind\":[],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1001\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1003\",\"subscribe\":[]}],\"name\":\"Secondary Element\"}],\"excluded\":false,\"features\":{\"friend\":2,\"lowPower\":2,\"proxy\":2,\"relay\":2},\"name\":\"iPhone\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"security\":\"secure\",\"unicastAddress\":\"7000\",\"UUID\":\"D709B6C3-1746-4310-A7AF-4649ACBB0E56\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"D2E1B7B7B7D6909B42561D7BF936FA73\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID001\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0001\",\"UUID\":\"23EFF5F1-FFA7-233D-BF7D-5402ED78CCF8\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"427CF8AA3A59CAE1C08433234E3B3D03\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID002\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0005\",\"UUID\":\"B0AACD91-E3EC-6233-8E75-B08703C257DF\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"B175432350374F6AC2543B4A62FEA664\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID003\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"0009\",\"UUID\":\"16360632-4144-A83A-B145-24FB38CE1D16\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"64043D84E6F3BC64813F1EFC98A9FD03\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID004\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"000D\",\"UUID\":\"D466E238-CB70-C03A-A5CD-F322B6631583\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"F9F0CDD34FF1378177FDA5F03D0CB837\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID005\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"0011\",\"UUID\":\"00593CC8-04EB-953D-8D26-8E870099B5FD\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"738DC1E1A84B50D7481A185CFD5E57D6\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID006\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0015\",\"UUID\":\"F49F2773-AA7A-2830-A8BD-87E09B0EE214\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"12B5969E3BC54A4CE1EFA9176A3E0D0C\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID007\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0019\",\"UUID\":\"9F0E9C40-638C-7B34-B312-19D9F0CDEEB0\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"4C8D8C916F229674DF674D3177120183\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID008\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"001D\",\"UUID\":\"AEC80B59-E994-9B36-92A4-CC004560E348\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"96709D52CBE167F411012A0A12A1C024\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID009\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"0021\",\"UUID\":\"9A33638C-E97B-9536-BB0B-1D268AB03049\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"9FB14971C5DF745F018C67E08AB0C8D5\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID010\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0025\",\"UUID\":\"65585992-2901-DF37-B170-33FFDD24111C\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"2B42E54EBD4419DD374A46744518EDA0\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID011\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0029\",\"UUID\":\"430D89C8-12DE-983D-B989-A5869BE8E253\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"E90C1007DA761AB1248E97F55FD3235B\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID012\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"002D\",\"UUID\":\"7DE8D6CD-31D0-1137-89A0-26220AEBDA68\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"12D890B9F63F4B049172E7A19EBB4603\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID013\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0031\",\"UUID\":\"628480EC-3A76-F539-A4CB-03037DD4B32B\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"AFBB6404D8F2AFA4687143A17E98D798\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID014\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0035\",\"UUID\":\"409642CD-5251-C43C-B2DF-FEE37EFB629F\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"792047BB33FAFEC05C9414FC1C5BEBF1\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID015\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0039\",\"UUID\":\"B5A6117F-0413-8634-88F0-0EA9CE5F2209\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"1BBB83E0C8DA3A5447AC66BDEE7F8BE1\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID016\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"003D\",\"UUID\":\"860A326A-A412-D933-A380-8A650A6EC172\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"DD73E8E21B80F0FCC9AF6368FA702DDC\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID017\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0041\",\"UUID\":\"8E20BC2A-770B-B832-96D3-66F2899128CE\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"2037311C55BD616FAC1474450F8A069A\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID018\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0045\",\"UUID\":\"F72C96D2-4A89-0239-80AF-479A38237B7E\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"B1CBE68A5CF173806D8F9612AF0A5DFF\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID019\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0049\",\"UUID\":\"947D2992-16E7-343D-A4AC-9D50DBEC981E\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"55BDC8DE89BACF6EF971C5E7A56D9F04\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID020\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"004D\",\"UUID\":\"206821C1-38F4-C73F-8437-232C15D529F1\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"BAF4E2858F980AD5EB4379D6540D1C9C\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID021\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0051\",\"UUID\":\"7B01A3FF-774F-193E-BBD6-2C0F9188FE58\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"D244740B431AF8BFF8F82DCC0202251C\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID022\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"0055\",\"UUID\":\"6F519203-CB49-3433-BF6B-97207FC31F84\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"EB8EE51A7ADA7ABDB52170BB917E07D7\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1303\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1304\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1307\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1308\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1306\",\"subscribe\":[]}]},{\"index\":2,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130A\",\"subscribe\":[]}]},{\"index\":3,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"130B\",\"subscribe\":[]}]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID023\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0005\",\"security\":\"insecure\",\"unicastAddress\":\"0059\",\"UUID\":\"94D50F47-5235-DD37-9916-A02EEC80B6CD\",\"vid\":\"3533\"},{\"appKeys\":[{\"index\":0,\"updated\":false}],\"cid\":\"0211\",\"configComplete\":false,\"crpl\":\"0069\",\"deviceKey\":\"3010559C3C3BFCCF74C5AE4CA4D5E3D3\",\"elements\":[{\"index\":0,\"location\":\"0000\",\"models\":[{\"bind\":[],\"modelId\":\"0000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"0003\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1000\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1002\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1004\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1006\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1007\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1203\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1204\",\"subscribe\":[]},{\"bind\":[0],\"modelId\":\"1300\",\"publish\":{\"address\":\"FFFF\",\"credentials\":0,\"index\":0,\"period\":{\"numberOfSteps\":16,\"resolution\":1000},\"retransmit\":{\"count\":0,\"interval\":50},\"ttl\":5},\"subscribe\":[]},{\"bind\":[],\"modelId\":\"1301\",\"subscribe\":[]},{\"bind\":[],\"modelId\":\"02110000\",\"subscribe\":[]}]},{\"index\":1,\"location\":\"0000\",\"models\":[]},{\"index\":2,\"location\":\"0000\",\"models\":[]},{\"index\":3,\"location\":\"0000\",\"models\":[]}],\"excluded\":false,\"features\":{\"lowPower\":2},\"name\":\"ID024\",\"netKeys\":[{\"index\":0,\"updated\":false}],\"pid\":\"0006\",\"security\":\"insecure\",\"unicastAddress\":\"005D\",\"UUID\":\"BF9A6538-B282-143F-9A24-E1F0007A447B\",\"vid\":\"3533\"}],\"partial\":true,\"provisioners\":[{\"allocatedGroupRange\":[{\"highAddress\":\"CC9A\",\"lowAddress\":\"C000\"}],\"allocatedSceneRange\":[{\"firstScene\":\"0001\",\"lastScene\":\"3333\"}],\"allocatedUnicastRange\":[{\"highAddress\":\"7FFF\",\"lowAddress\":\"0001\"}],\"provisionerName\":\"iPhone\",\"UUID\":\"D709B6C3-1746-4310-A7AF-4649ACBB0E56\"}],\"scenes\":[],\"timestamp\":\"2024-01-09T06:54:22Z\",\"version\":\"1.0.1\"}"

extension SiteData {
    
    /// 添加场所
    /// - Parameter name: 场所名称
    /// - Returns: 场所
    static func add(name: String) -> SiteData {
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        let site = SiteData(id: UUID().uuidString, name: name, imageId: 1, type: .office, create: "\(time)",isFavourite: false, sourceType: .create)
        site.save()
        return site
    }
    
    /// 场所添加空间
    /// - Parameters:
    ///   - name: 空间名称
    ///   - id: 空间id
    ///   - imageId: 空间图片id
    /// - Returns: 空间
    func addSpace(name: String, id: String = UUID().uuidString, imageId: Int = 1) -> SpaceData {
        
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        let space = SpaceData(name: name, id: id, siteId: self.id, imageId: imageId, create: "\(time)", isFavourite: false, sourceType: .create, meshUUID: id)
        addSpace(space)
        return space
    }
     
    /// 场所添加空间
    /// - Parameter space: 空间数据
    func addSpace(_ space: SpaceData) {
        // 没有对应mesh网络时创建一个网络
//        if MeshNetworkManager.loadMeshNetwork(meshUUID: space.meshUUID) == nil {
//            /// 测试数据
//            var meshManager = MeshLibManager.manager.createMeshNetwork(meshUUID: space.meshUUID, meshNetworkName: space.name, connected: false)
//            if meshManager.realNodes.isEmpty {
//                let meshData = testMeshJsonDataString.data(using: .utf8)!
//                do {
//                    if var meshDict = try JSONSerialization.jsonObject(with: meshData) as? [String: Any] {
//                        meshDict.updateValue(space.meshUUID, forKey: "meshUUID")
//                        let setData = try JSONSerialization.data(withJSONObject: meshDict)
//                        _ = try meshManager.import(from: setData)
//                        _ = meshManager.save()
//                    }
//                } catch {
//                    
//                }
//            }
//        }
        
        MeshLibManager.manager.createMeshNetwork(meshUUID: space.meshUUID, meshNetworkName: space.name, connected: false)
        space.save()
        spaces.append(space)
    }
    
    /// 克隆场所数据
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SiteData {
        let siteData = self.cloneData()
        let spaces = self.spaces.map({ $0.clone() })
        siteData.spaces = spaces
        if save {
            siteData.save(allData: true)
        }
        return siteData
    }
}

extension SpaceData {
    
    private struct AssociatedKey {
        static var meshManagerKey = 1
        static var testMeshManagerKey = 2
    }
    
    var meshManager: MeshNetworkManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.meshManagerKey) as? MeshNetworkManager ??
            MeshNetworkManager.loadMeshNetwork(meshUUID: id)
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.meshManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var testMeshManager: MeshNetworkManager? {
        get {
            guard let meshManager = objc_getAssociatedObject(self, &AssociatedKey.testMeshManagerKey) as? MeshNetworkManager else {
                
                let meshData = testMeshJsonDataString.data(using: .utf8)!
                do {
                    let meshManager = MeshNetworkManager.createMeshNetwork()
                    _ = try meshManager.import(from: meshData)
                    meshManager.realNodes.forEach({
                        $0.macAddress = String(format: "AA67BE00%04d", $0.primaryUnicastAddress)
                    })
                    self.testMeshManager = meshManager
                    return meshManager
                }catch {
                    
                }
                return nil
            }
         return meshManager
            
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.testMeshManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
    /// 测试节点数据
    var testNodes: [Node] {
        return testMeshManager?.realNodes ?? []
    }
    
    var nodes: [Node] {
        return meshManager?.realNodes ?? []
    }
    
    var groups: [Group] {
        return meshManager?.groups ?? []
    }
    
    var scenes: [Scene] {
        return meshManager?.scenes ?? []
    }
    
    var schedules: [Schedule] {
        return meshManager?.schedules ?? []
    }
    
    /// 获取下一个节点名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的节点名称
    func getNextNodeName(_ defalutName: String = "device_defalut_name".localizedString) -> String {
        objc_sync_enter(self)
        
        var resultName = defalutName + "001"
        // 已存在的节点名称
        let existNames = self.nodes.map({ $0.name ?? "" })
        for index in 1...32767 {
            // ID001
            let name = defalutName + String(format: "%03d", index)
            if !existNames.contains(name) {
                resultName = name
                break
            }
        }
        objc_sync_exit(self)
        return resultName
        
    }
    
    /// 设备节点是否重名
    /// - Parameter nodeName: 节点名称
    /// - Returns: 是否重名
    func isNodeTautonym(nodeName: String) -> Bool {
        return nodes.contains(where: { $0.name == nodeName })
    }
    
    /// 获取下一个场景名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的场景名称
    func getNextSceneName(_ defalutName: String = "scene_defalut_name".localizedString) -> String {
        // 已存在的场景名称
        let existNames = scenes.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 场景是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isSceneTautonym(name: String) -> Bool {
        return scenes.contains(where: { $0.name == name })
    }
    
    /// 获取下一个组名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的组名称
    func getNextGroupName(_ defalutName: String = "group_defalut_name".localizedString) -> String {
        // 已存在的组名称
        let existNames = groups.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 组是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isGroupTautonym(name: String) -> Bool {
        return groups.contains(where: { $0.name == name })
    }
    
    /// 获取下一个日程名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的日程名称
    func getNextScheduleName(_ defalutName: String = "schedule_defalut_name".localizedString) -> String {
        // 已存在的日程名称
        let existNames = schedules.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 获取下一个日程id 0~15
    func getNextAvailableScheduleId() -> Int? {
        for id in 0...15 {
            if !schedules.contains(where: { $0.id == id }) {
                return id
            }
        }
        return nil
    }
    
    /// 日程是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isScheduleTautonym(name: String) -> Bool {
        return schedules.contains(where: { $0.name == name })
    }
    
    /// 克隆空间数据（空间信息、mesh网络数据）
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SpaceData {
        
        let spaceData = self.cloneData()
        // 创建的mesh网络
        let meshManager = MeshNetworkManager.createMeshNetwork(meshUUID: spaceData.id, meshNetworkName: spaceData.name)
        // 克隆目标的mesh网络，同步数据
        if let cloneMeshManager = spaceData.meshManager {
            // clone 组，场景，日程，节律等这些能够预设的参数。（目前只有组、场景）
            cloneMeshManager.groups.forEach { group in
                try? meshManager.meshNetwork?.add(group: group)
            }
            cloneMeshManager.scenes.forEach { scene in
                try? meshManager.meshNetwork?.add(scene: scene.number, name: scene.info.name ?? scene.name)
            }
        }
        _ = meshManager.save()
        if save {
            spaceData.save()
        }
        return spaceData
    }
    
    /// 删除空间数据+mesh网络
    @discardableResult func delete() -> Bool {
        
        // 删除mesh网络文件并断开连接
//        MeshLibManager.manager.removeMeshNetwork(meshUUID: self.meshUUID)
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
        _ = MeshNetworkManager.removeMeshNetwork(meshUUID: self.meshUUID)
        // 删除网络扩展数据
        _ = GroupInfo.deleteAll(meshUUID: meshUUID)
        _ = SceneInfo.deleteAll(meshUUID: meshUUID)
        _ = SceneExecuteData.deleteAll(meshUUID: meshUUID)
        _ = Schedule.deleteAll(meshUUID: meshUUID)
        _ = Node.deleteAllInfo(meshUUID: meshUUID)
        _ = Node.deleteAllSchedule(meshUUID: meshUUID)
        
        return self.deleteData()
    }
    
}

extension MeshNetworkManager {
    
    private static var schedulesKey = 0
    
    /// 日程list
    var schedules: [Schedule] {
        get {
            objc_getAssociatedObject(self, &MeshNetworkManager.schedulesKey) as? [Schedule] ?? []
        }set {
            objc_setAssociatedObject(self, &MeshNetworkManager.schedulesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 获取网络扩展数据
    func loadExtensionData() {
        
        guard let uuid = self.meshNetwork?.uuid.uuidString else { return }
        
        realNodes.forEach({
            $0.loadExtendInfo()
        })
        
        groups.forEach({
            if let info = GroupInfo.load(meshUUID: uuid, address: $0.address.address) {
                $0.info = info
            }
        })
        
        schedules = Schedule.loadAll(meshUUID: uuid)
        
        scenes.forEach({
            if let info = SceneInfo.load(meshUUID: uuid, sceneId: Int($0.number)) {
                $0.info = info
                let sceneSchedules = $0.info.bindSchedules
                $0.info.groups.forEach({ group in
                    sceneSchedules.forEach({ sceneSchedule in
                        if !group.info.bindSchedules.contains(where: {$0.id == sceneSchedule.id }) {
                            group.info.bindSchedules.append(sceneSchedule)
                        }
                    })
                })
            }
        })
        
    }
    
}

extension Group {
    
    private static var infoKey = 0
    private static var lightnessKey = 1
    private static var cctKey = 2
    private static var isOnKey = 3
    
    static let defaultLightness: UInt16 = .max
    static let defaultCct: Int = 4500
    
    /// 扩展信息
    var info: GroupInfo {
        get {
            objc_getAssociatedObject(self, &Group.infoKey) as? GroupInfo ?? GroupInfo(address: address.address, name: name, imageId: 0)
        }set {
            objc_setAssociatedObject(self, &Group.infoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组亮度值 0~65535
    var lightness: UInt16 {
        get {
            // 缓存值->相同频率最高值->默认值
            // 读取缓存
            guard let lightness = objc_getAssociatedObject(self, &Group.lightnessKey) as? UInt16 else {
                if nodes.isEmpty {
                    return 65535
                }
                // 计算频率最高值 出现次数>1
                let lightnesss = self.nodes.filter({ $0.lightnessModel != nil }).map({ $0.lightness })
                var lightnessValueList: [NSMutableArray] = []
                lightnesss.forEach { value in
                    if let values = lightnessValueList.first(where: { $0.contains(value) }) {
                        values.add(value)
                    }else {
                        lightnessValueList.append(NSMutableArray(object: value))
                    }
                }
                // 默认值
                var lightness = Group.defaultLightness
                if let values = lightnessValueList.max(by: { $1.count > $0.count }), values.count > 1 {
                    lightness = values.firstObject as! UInt16
                }
                return lightness
            }
            return lightness
        }set {
            objc_setAssociatedObject(self, &Group.lightnessKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组色温值 2700K-6500K
    var cct: Int {
        get {
            // 缓存值->相同频率最高值->默认值
            // 读取缓存
            guard let cct = objc_getAssociatedObject(self, &Group.cctKey) as? Int else {
                if nodes.isEmpty {
                    return 4500
                }
                // 计算频率最高值 出现次数>1
                let ccts = self.nodes.filter({ $0.temperatureModel != nil || $0.ctlModel != nil }).map({ $0.temperature })
                var cctValueList: [NSMutableArray] = []
                ccts.forEach { value in
                    if let values = cctValueList.first(where: { $0.contains(value) }) {
                        values.add(value)
                    }else {
                        cctValueList.append(NSMutableArray(object: value))
                    }
                }
                // 默认值
                var cct = Group.defaultCct
                if let values = cctValueList.max(by: { $1.count > $0.count }), values.count > 1 {
                    cct = values.firstObject as! Int
                }
                return cct
            }
            return cct
        }set {
            objc_setAssociatedObject(self, &Group.cctKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组开关
    var isOn: Bool {
        get {
            objc_getAssociatedObject(self, &Group.isOnKey) as? Bool ?? (nodes.isEmpty || nodes.contains(where: { $0.isOn }))
        }set {
            objc_setAssociatedObject(self, &Group.isOnKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否支持onoff
    var supportOnOff: Bool {
        return nodes.contains(where: { $0.onoffModel != nil })
    }
    
    /// 是否支持亮度
    var supportLightness: Bool {
        return nodes.contains(where: { $0.lightnessModel != nil })
    }
    
    /// 是否支持色温
    var supportCct: Bool {
        return nodes.contains(where: { $0.temperatureModel != nil || $0.ctlModel != nil })
    }
    
    /// 删除本地化缓存数据（只处理业务扩展数据）
    func delete() {
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 删除基本信息
        GroupInfo.delete(meshUUID: uuid, address: address.address)
        // 删除组设置的场景数据
        SceneExecuteData.deleteData(meshUUID: uuid, address: address.address)
        MeshNetworkManager.instance.scenes.forEach({
            if let index = $0.info.groups.firstIndex(of: self) {
                $0.info.groups.remove(at: index)
            }
        })
        
        // 删除组设置的日程数据
        MeshNetworkManager.instance.schedules.forEach({
            if let index = $0.groups.firstIndex(of: self) {
                $0.groups.remove(at: index)
                $0.save(meshUUID: uuid)
            }
            if let index = $0.needDeleteGroups.firstIndex(of: self) {
                $0.needDeleteGroups.remove(at: index)
                $0.save(meshUUID: uuid)
            }
        })
        
    }
    
    /// 删除组内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
      
        self.info.bindSceneDatas.removeValue(forKey: sceneId)
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        SceneExecuteData.deleteData(meshUUID: uuid, address: address.address, sceneId: Int(sceneId))
    }
    
    /// 更新组内的场景状态
    /// - Parameter sceneId: 场景id
    func updateSceneState(sceneId: SceneNumber, state: SceneExecuteData.State) {
      
        if let sceneData = self.info.bindSceneDatas[sceneId] {
            sceneData.state = state
            guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
                return
            }
            SceneExecuteData.save(meshUUID: uuid, address: address.address, sceneId: Int(sceneId), sceneData: sceneData)
        }
    }
    
    /// 本地化缓存组数据（只处理业务扩展数据）
    func save() {
        
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 保存基本信息
        self.info.save(meshUUID: uuid)
        // 保存场景数据
        self.info.bindSceneDatas.forEach({
            SceneExecuteData.save(meshUUID: uuid, address: address.address, sceneId: Int($0.key), sceneData: $0.value)
        })
        
    }
    
    
    /// 获取组需要同步对应场景的设备
    /// - Parameter scene: 场景
    /// - Returns: 待同步的设备、待删除场景的设备
    func getNeedSyncDataNodes(scene: Scene) -> (syncNodes: [Node], deleteNodes: [Node]) {
        // 需要同步场景参数的设备list
        var needSyncNodes: [Node] = []
        // 需要删除场景参数的设备list
        var needDeleteNodes: [Node] = []
        guard let sceneData = info.bindSceneDatas[scene.number] else {
            return (needSyncNodes, needDeleteNodes)
        }
        if sceneData.state == .waitDelete { // 待删除
            needDeleteNodes = nodes.filter({ $0.sceneDatas.contains(where: { $0.key == scene.number }) })
        }else { // 同步
            needSyncNodes = nodes.filter({
                if let nodeSceneData = $0.sceneDatas.first(where: { $0.key == scene.number })?.value {
                    return !(nodeSceneData == sceneData)
                }
                return true
            })
        }
        return (needSyncNodes, needDeleteNodes)
    }
    
    /// 获取组需要同步对应日程的设备
    /// - Parameter schedule: 日程
    /// - Returns: 待同步的设备、待删除日程的设备
    func getNeedSyncScheduleDataNodes(_ schedule: Schedule) -> (syncNodes: [Node], deleteNodes: [Node]) {
        
        // 需要同步日程参数的设备list
        var needSyncNodes: [Node] = []
        // 需要删除日程参数的设备list
        var needDeleteNodes: [Node] = []
        guard info.bindSchedules.contains(where: { $0.id == schedule.id }) else {
            return (needSyncNodes, needDeleteNodes)
        }
        
        // 待删除的组,获取组内待删除的设备
        if schedule.needDeleteGroups.contains(self) {
            needDeleteNodes = self.nodes.filter({ $0.scheduleDatas.keys.contains(schedule.id) })
        }else { // 待同步，获取组内待同步的设备
            needSyncNodes = self.nodes.filter({ !$0.scheduleDatas.keys.contains(schedule.id) || !($0.scheduleDatas[schedule.id]! == schedule.schedulerEntry) })
        }
        return (needSyncNodes, needDeleteNodes)
    }

}

extension Scene {
    
    private static var infoKey = 0
    /// 扩展信息
    var info: SceneInfo {
        get {
            objc_getAssociatedObject(self, &Scene.infoKey) as? SceneInfo ?? SceneInfo(sceneId: self.number, name: name, imageId: 0)
        }set {
            objc_setAssociatedObject(self, &Scene.infoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 获取需要同步数据的组
    var needSyncGroups: [Group] {
        info.groups.filter({ group in
            let sceneResult = group.getNeedSyncDataNodes(scene: self)
            let isSyncScene = sceneResult.syncNodes.count > 0 || sceneResult.deleteNodes.count > 0
            let isSyncSchedule = info.bindSchedules.contains(where: {
                let scheduleSyncResult = group.getNeedSyncScheduleDataNodes($0)
                return scheduleSyncResult.syncNodes.count > 0 || scheduleSyncResult.deleteNodes.count > 0
            })
            return isSyncSchedule || isSyncScene
        })
        
    }
    
    
    /// 删除场景缓存数据
    func delete() {
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 删除场景内组缓存数据
        info.groups.forEach({
            if $0.info.bindSceneDatas[number] != nil {
                SceneExecuteData.deleteData(meshUUID: uuid, address: $0.address.address, sceneId: Int(number))
                $0.info.bindSceneDatas.removeValue(forKey: number)
            }
            // 删除组内设备缓存的场景数据
            $0.nodes.forEach({ node in
                if node.sceneDatas[number] != nil {
                    SceneExecuteData.deleteData(meshUUID: uuid, address: node.primaryUnicastAddress, sceneId: Int(number))
                    node.sceneDatas.removeValue(forKey: number)
                }
            })
        })
        info.groups.removeAll()
        SceneInfo.delete(meshUUID: uuid, sceneId: self.number)
    }
    

    /// 本地化缓存组数据（只处理业务扩展数据）
//    func save() {
//        
//        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
//            return
//        }
//        // 保存基本信息
//        self.info.save(meshUUID: uuid)
//        // 保存场景数据
//        self.info.groups.forEach({
//            SceneExecuteData.save(meshUUID: uuid, address: $0.address.address, sceneId: Int(sceneId), sceneData: data)
//        })
//    }
    
    
}

class SceneInfo {
    
    /// 场景id
    var sceneId: UInt16 = 0
    
    /// 场景名称
    var name: String?
    
    /// 图片id
    var imageId: Int = 0
    
    /// 添加的组list
    var groups: [Group] = []
    
    /// 场景内绑定的日程list
    var bindSchedules: [Schedule] {
        return MeshNetworkManager.instance.schedules.filter({ $0.scene?.number == self.sceneId })
    }
    
    
    init(sceneId: UInt16, name: String? = nil, imageId: Int, groups: [Group] = []) {
        self.sceneId = sceneId
        self.name = name
        self.imageId = imageId
        self.groups = groups
    }
}

class GroupInfo {
    
    /// 组地址
    var address: UInt16 = 0
    
    /// 组名称
    var name: String?
    
    /// 图片id
    var imageId: Int = 0
    
    /// 图标文本（自定义）
    var imageText: String?
    
    /// 绑定的场景数据
    var bindSceneDatas: [SceneNumber : SceneExecuteData] = [:]
    
    /// 绑定的日程数据
    var bindSchedules: [Schedule] = []
    
    init(address: UInt16, name: String? = nil, imageId: Int, imageText: String? = nil, bindSceneDatas: [SceneNumber : SceneExecuteData] = [:], bindSchedules: [Schedule] = []) {
        self.address = address
        self.name = name
        self.imageId = imageId
        self.imageText = imageText
        self.bindSceneDatas = bindSceneDatas
        self.bindSchedules = bindSchedules
    }
}

/// 场景执行数据
class SceneExecuteData {
    
    /// 场景执行数据色温范围
    static let cctRange: ClosedRange<UInt16> = 2700...6500
    
    /// 状态
    enum State: Int {
        /// 正常
        case normal = 1
        /// 待删除（删除失败）
        case waitDelete = 2
    }
    
    /// 亮度 0~100
    var lightness: Int = 0
    /// 色温
    var cct: Int = 0
    /// 状态 1:正常  2:删除
    var state: State = .normal
    
    init(lightness: Int, cct: Int, state: State = .normal) {
        self.lightness = lightness
        self.cct = cct
        self.state = state
    }
    
    static func == (lhs: SceneExecuteData, rhs: SceneExecuteData) -> Bool {
        return lhs.lightness == rhs.lightness && lhs.cct == rhs.cct
    }
}

class Schedule: Copyable {
    
    /// 重复周期字符串list
    static let weeklyStrs = ["week_mo".localizedString, "week_tu".localizedString, "week_we".localizedString, "week_th".localizedString, "week_fr".localizedString, "week_sa".localizedString, "week_su".localizedString]
    
    /// 日程执行目标类型
    enum TargetType: Int {
        /// 组
        case groups = 0
        /// 设备
        case devices = 1
        /// 设备
        case scene = 2
    }
    
    /// 计划id  0~15
    var id: Int = 0
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String = ""
    /// 设置的节点list nodes、groups、scenes三选一
    var nodes: [Node] = []
    /// 设置的组list nodes、groups、scenes三选一
    var groups: [Group] = []
    /// 设置执行的场景，目前只能设置一个，并且nodes、groups、scenes三选一
    var scene: Scene?
    /// 选择的执行目标类型
    var selectTargetType: TargetType = .groups
    /// 执行的场景id
//    var actionSceneId: SceneNumber = 0
    /// 执行动作 off、on、recall scene、no action
    var action: SchedulerAction = .noAction
    /// 渐变时间（s）
    var fadeTime: Int = 0
    /// 周重复
    var weekDays: [WeekDay] = []
    /// 时
    var hour: Int = 0
    /// 分
    var minute: Int = 0
    /// 创建时间（时间戳毫秒）
    var create: String
    /// 最近更新的时间（时间戳毫秒）
    var lastUpdate: String
    /// 需要移出日程的设备
    var needDeleteNodes: [Node] = []
    /// 需要移出日程的组
    var needDeleteGroups: [Group] = []
    /// 需要移出的日程的场景
    var needDeleteScenes: [Scene] = []
    /// 存在的设备
    var exitNodes: [Node] {
        var nodes: [Node] = []
        nodes.append(contentsOf: self.nodes)
        nodes.append(contentsOf: self.needDeleteNodes.filter({ !nodes.contains($0) }))
        
        groups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        needDeleteGroups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        
        scene?.info.groups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        needDeleteScenes.forEach { scene in
            scene.info.groups.forEach({
                nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
            })
        }
        return nodes
    }
    
    
    /// 重复周期描述
    var weekStr: String {
        
        let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        
        var weekStr = ""
        if weekDays == allWeekDays { // 每天
            weekStr = "everyday".localizedString
        }else if weekDays == allWeekDays.dropLast(2) { // 工作日
            weekStr = "workday".localizedString
        }else if weekDays == allWeekDays.suffix(2) { // 周末
            weekStr = "weekend".localizedString
        }else { // 无规律 Mo, Tu, We, Fr, Sa, Su
            let weekStrs = weekDays.compactMap({
                if let index = allWeekDays.firstIndex(of: $0) {
                    return Schedule.weeklyStrs[min(Schedule.weeklyStrs.count, index)]
                }
                return nil
            })
            
            weekStrs.forEach({
                weekStr.append(weekStr.isEmpty ? $0 : ",\($0)")
            })
        }
        
        return weekStr
    }
    
    
    /// 设置的数据
    var data: Data {
        return SchedulerRegistryEntry.marshal(index: UInt8(id), entry: schedulerEntry)
    }
    /// 设备的日程数据
    var schedulerEntry: SchedulerRegistryEntry {
//        日程删除 => (action=noAction)
//        日程关闭=>  (month=空 && action != noAction)
        let allMonths: [Month] = enabled ? [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December] : []
        let entry = SchedulerRegistryEntry(year: .any(), month: .any(of: allMonths), day: .any(), hour: .specific(hour: hour), minute: .specific(minute: minute), second: .specific(second: 0), dayOfWeek: .any(of: weekDays), action: action, transitionTime: .init(steps: UInt8(fadeTime), stepResolution: .seconds), sceneNumber: scene?.number ?? 0)
        return entry
    }
    
    
    
    init(id: Int, name: String, enabled: Bool, nodes: [Node] = [], groups: [Group] = [], scene: Scene?, selectTargetType: TargetType = .groups, action: SchedulerAction, fadeTime: Int, weekDays: [WeekDay], hour: Int, minute: Int, create: String, lastUpdate: String? = nil) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.nodes = nodes
        self.groups = groups
        self.scene = scene
        self.selectTargetType = selectTargetType
        self.action = action
        self.fadeTime = fadeTime
        self.weekDays = weekDays
        self.hour = hour
        self.minute = minute
        self.create = create
        self.lastUpdate = lastUpdate ?? create
    }
    
    /// 复制日程
    func copy() -> Self {
        let schedule = Schedule(id: id, name: name, enabled: enabled, nodes: nodes, groups: groups, scene: scene, selectTargetType: selectTargetType, action: action, fadeTime: fadeTime, weekDays: weekDays, hour: hour, minute: minute, create: create, lastUpdate: lastUpdate)
        return schedule as! Self
    }
    
    
    /// 更新日程数据
    /// - Parameter entry: 设备日程数据
    func updata(entry: SchedulerRegistryEntry) {
        
        self.enabled = entry.month.value > 0 && entry.action != .noAction
        self.action = entry.action
        if let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == entry.sceneNumber }) {
            self.scene = scene
        }
        self.fadeTime = Int(entry.transitionTime.steps)
        
        // 计算选中的重复周期
        self.weekDays = Schedule.getWeekDays(weekValue: Int(entry.dayOfWeek.value))
        self.hour = Int(entry.hour.value)
        self.minute = Int(entry.minute.value)
    }
    
    /// 根据周重复值获取重复周期
    static func getWeekDays(weekValue: Int) -> [WeekDay] {
        let allWeekDays :[WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        var selectWeekDays: [WeekDay] = []
        for (weekInt, weekDay) in allWeekDays.enumerated() {
            if weekValue >> weekInt & 1 == 1 {
                selectWeekDays.append(weekDay)
            }
        }
        return selectWeekDays
    }
    
    /// 根据重复周期获取周重复值
    static func getWeekValue(weekDays: [WeekDay]) -> Int {
        return Int(weekDays.reduce(0, { (result, day) -> UInt8 in result + day.rawValue}))
    }
    
    static func == (lhs: Schedule, rhs: Schedule) -> Bool {
        
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.enabled == rhs.enabled && lhs.selectTargetType == rhs.selectTargetType && lhs.scene?.number == rhs.scene?.number && lhs.action == rhs.action && lhs.fadeTime == rhs.fadeTime && lhs.weekDays == rhs.weekDays && lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }
    
    /// 获取日程需要同步/删除的数据
    /// nodes：add/remove  【Node】
    /// groups：add/remove 【(group: [Node])】
    /// scene: add/remove  【(scene：[Group])】
    func getNeedSyncDatas() -> ScheduleSyncData {
        
        var syncNodes: [Node] = []
        var syncGroupData: [Group: [Node]] = [:]
        
//        var allSetScheduleNodes: [Node] = []
        
        // 所有需要同步的设备 直接关联-间接关联（组、场景）只设置一次不需要重复同步
        var allSyncNodes: [Node] = []
        // 所有需要删的设备 直接关联-间接关联（组、场景） 只删除一次不需要重复删除
//        var allDeleteNodes: [Node] = []
        
        switch selectTargetType {
        case .devices:
            syncNodes = nodes.filter({ $0.scheduleDatas[id] == nil || !($0.scheduleDatas[id]! == schedulerEntry) })
            allSyncNodes.append(contentsOf: nodes)
        case .groups:
            groups.forEach({
                let groupSyncNodes = $0.nodes.filter({ $0.scheduleDatas[id] == nil || !($0.scheduleDatas[id]! == schedulerEntry) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: $0)
                }
                allSyncNodes.append(contentsOf: $0.nodes)
            })
        case .scene:
            scene?.info.groups.forEach({
                let groupSyncNodes = $0.nodes.filter({ $0.scheduleDatas[id] == nil || !($0.scheduleDatas[id]! == schedulerEntry) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: $0)
                }
                allSyncNodes.append(contentsOf: $0.nodes)
            })
        }
        
        let deleteNodes = needDeleteNodes.filter({ !allSyncNodes.contains($0) })
        
        var deleteGroupData: [Group: [Node]] = [:]
        needDeleteGroups.forEach({
            let groupDeleteNodes = $0.nodes.filter({ $0.scheduleDatas[id] != nil && !allSyncNodes.contains($0) && !deleteNodes.contains($0) })
            // ((!allSyncNodes.contains($0) && !allDeleteNodes.contains($0)) || !nodes.contains($0))
            if groupDeleteNodes.count > 0 {
                deleteGroupData.updateValue(groupDeleteNodes, forKey: $0)
//                allDeleteNodes.append(contentsOf: groupDeleteNodes)
            }
        })

        needDeleteScenes.forEach({ scene in
            scene.info.groups.forEach { group in
                let groupDeleteNodes = group.nodes.filter({ $0.scheduleDatas[id] != nil && !allSyncNodes.contains($0) && !deleteNodes.contains($0) })
                // && !allSyncNodes.contains($0)) && !allDeleteNodes.contains($0)
                if groupDeleteNodes.count > 0 {
                    deleteGroupData.updateValue(groupDeleteNodes, forKey: group)
//                    allDeleteNodes.append(contentsOf: groupDeleteNodes)
                }
            }
        })
        
        let data = ScheduleSyncData(syncNodes: syncNodes, deleteNodes: deleteNodes, syncGroups: syncGroupData, deleteGroups: deleteGroupData)
        return data
    }
    
    /// 日程同步数据
    struct ScheduleSyncData {
        /// 需要同步的节点
        var syncNodes: [Node] = []
        /// 需要删除的节点
        var deleteNodes: [Node] = []

        /// 需要同步的组-设备
        var syncGroups: [Group: [Node]] = [:]
        /// 需要删除的组-设备
        var deleteGroups: [Group: [Node]] = [:]
  
        /// 是否空数据
        func isEmpty() -> Bool {
            return syncNodes.isEmpty && deleteNodes.isEmpty && syncGroups.isEmpty && deleteGroups.isEmpty
        }
    }

}

extension Node {
    /// 设备对应组状态
    enum GroupState: Int {
        /// 无（未加入）
        case none = 0
        /// 在组内
        case inGroup = 1
        /// 退出组失败
        case exitFailure = 2
    }
    
    static private var bindSceneDatasKey = 1
    static private var schedulesKey = 2
    static private var groupStateKey = 2
    
    /// 设备对应组状态
    var groupState: GroupState {
        get {
            objc_getAssociatedObject(self, &Node.groupStateKey) as? GroupState ?? (group != nil ? .inGroup : .none)
        }set {
            objc_setAssociatedObject(self, &Node.groupStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 节点缓存的场景数据
    var sceneDatas: [SceneNumber: SceneExecuteData] {
        get {
            objc_getAssociatedObject(self, &Node.bindSceneDatasKey) as? [SceneNumber: SceneExecuteData] ?? [:]
        }set {
            objc_setAssociatedObject(self, &Node.bindSceneDatasKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 节点缓存的日程数据（设置成功）
    var scheduleDatas: [Int: SchedulerRegistryEntry] {
        get {
            objc_getAssociatedObject(self, &Node.schedulesKey) as? [Int: SchedulerRegistryEntry] ?? [:]
        }set {
            objc_setAssociatedObject(self, &Node.schedulesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// mac地址分割
    var macAddressResult: String? {
        if let macAddress = macAddress, !macAddress.isEmpty {
            var result = ""
            var offset = 0
            for _ in 0..<Int(macAddress.count / 2) {
                if offset + 2 > macAddress.count { break }
                let string = macAddress.subString(rang: NSRange(location: offset, length: 2))
                offset += 2
                result.append(String(format: "%@%@", result.isEmpty ? "" : ":", string))
            }
            return result
        }
        return nil
    }
    
    /// 是否需要同步数据
    var needSync: Bool {
        return !getNeedSyncGroupData().isEmpty()
    }
    
    /// 获取设备需要同步组的数据
    /// - Parameter group: 传入需要加入的组，不传则当前组
    func getNeedSyncGroupData(group: Group? = nil) -> SyncData {
        
        var data = SyncData()
        guard let group = group ?? self.group else {
            return data
        }
        
        if groupState == .exitFailure { // 设备退出组失败
            data.unsubscribeGroup = true
        }else if getSubscribeToGroupMessages(group).count > 0 { // 设备订阅组数据不完整
            data.subscribeGroup = true
        }
        // 组内待删除的场景
        let deleteScenes = group.info.bindSceneDatas.filter({ $0.value.state.rawValue == 2 })
        // 组内待删除的日程
        let deleteSchedules = group.info.bindSchedules.filter({ schedule in
            return schedule.needDeleteGroups.contains(where: { $0.address.address == group.address.address })
        })
        
        // 设备待删除的场景list
        let nodeDeleteScenes = self.scenes.filter({ deleteScenes.keys.contains($0.number) })
        // 设备待同步的场景list
        let nodeSyncScenes = group.info.bindSceneDatas.filter({ self.sceneSetupModel != nil && (!self.sceneDatas.keys.contains($0.key) || !(self.sceneDatas[$0.key]! == $0.value)) })
        // 设备待删除的日程list
        _ = deleteSchedules.filter({ schedule in self.scheduleDatas.contains(where: { $0.key == schedule.id }) })
        // 设备待同步的日程list
        let nodeSyncSchedules: [Schedule] = group.info.bindSchedules.filter { schedule in
            !self.scheduleDatas.contains(where: { $0.key == schedule.id }) || !self.scheduleDatas.contains(where: { $0.value == schedule.schedulerEntry })
        }
        
        data.syncScenes = nodeSyncScenes
        data.syncSchedules = nodeSyncSchedules
        data.deleteScenes = nodeDeleteScenes
        data.deleteSchedules = deleteSchedules
        
        return data
    }

    
    /// 根据色温范围获取对应色温颜色
    /// - Parameter cct100: 0~100色温
    /// - Returns: 对应色温颜色
    static func getCctMixColor(temperature100: Int) -> UIColor {
        // 暖色
        let components1 = RGB(255, 108, 0).cgColor.components!
        // 过渡色
        let components2 = RGB(255, 255, 255).cgColor.components!
        // 冷色
        let components3 = RGB(114, 179, 255).cgColor.components!
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        // 0~1比例
        var ratio: CGFloat = 0
        switch temperature100 {
        case 0...50: // 0~50取暖色到过渡色的混色
            ratio = CGFloat(temperature100) / 50.0
            r = components2[0] * ratio + components1[0] * (1.0 - ratio)
            g = components2[1] * ratio + components1[1] * (1.0 - ratio)
            b = components2[2] * ratio + components1[2] * (1.0 - ratio)
        case 50...100: // 50~100取过渡色到冷色的混色
            ratio = CGFloat(temperature100 - 50) / 50.0
            r = components3[0] * ratio + components2[0] * (1.0 - ratio)
            g = components3[1] * ratio + components2[1] * (1.0 - ratio)
            b = components3[2] * ratio + components2[2] * (1.0 - ratio)
        default:
            break
        }
        let color =  UIColor(red: r, green: g, blue: b, alpha: 1)
        return color
    }
    
    /// 获取设备所有扩展数据
    func loadExtendInfo() {
        
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        if let info = Node.loadNodeInfo(meshUUID: uuid, address: primaryUnicastAddress) {
            self.lightCTLTemperatureRange = info.cctRange
            self.groupState = info.groupState
            self.scheduleDatas = info.schedules
            self.sceneDatas = info.sceneDatas
            self.scheduleIds = self.scheduleDatas.compactMap({
                if $0.value.isValid {
                    return $0.key
                }
                return nil
            })
            
            self.schedulerActions = self.scheduleDatas.filter({ $0.value.isValid })
//            self.rssi = info.rssi
        }
        
        let sceneDataList = SceneExecuteData.loadAll(meshUUID: uuid, address: primaryUnicastAddress)
        var sceneDatas: [SceneNumber: SceneExecuteData] = [:]
        sceneDataList.forEach({
            sceneDatas.updateValue($0.data, forKey: SceneNumber($0.sceneId))
        })
        self.sceneDatas = sceneDatas
        
    }
    
    /// 删除设备缓存的所有扩展数据
    func delete() {
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        // 删除设备缓存信息
        Node.deleteInfo(meshUUID: uuid, address: primaryUnicastAddress)
        // 删除设备场景数据
        SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress)
        // 删除设备日程数据
        Node.deleteSchedules(meshUUID: uuid, address: primaryUnicastAddress)
    }
    
    /// 删除节点内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
      
        sceneDatas.removeValue(forKey: sceneId)
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId))
    }
    
    /// 本地化缓存设备数据
    func save() {
        
        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return
        }
        
        saveNodeInfo(meshUUID: uuid)
        
        scheduleDatas.forEach({
            Node.saveSchedule(meshUUID: uuid, address: primaryUnicastAddress, scheduleId: $0.key, entry: $0.value)
        })
        
        sceneDatas.forEach({
            SceneExecuteData.save(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int($0.key), sceneData: $0.value)
        })
        
        
    }
    
    
    /// 更新节点缓存数据
    /// - Parameter messageHandle: 消息发送操作对象
    func updateData(message: MeshMessage) {
       
        let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
//        let isSuccess = messageHandle.isFinished
//        let message = messageHandle.message
        switch message {
        case is ConfigModelSubscriptionAdd:
            self.groupState = .inGroup
            
        case is ConfigModelSubscriptionDelete:
            self.groupState = self.group != nil ? .inGroup : .exitFailure
            
        case is SceneStore:
            let sceneId = (message as! SceneStore).scene
            let executeData = SceneExecuteData(lightness: self.lightness100, cct: self.temperature100, state: .normal)
            self.sceneDatas.updateValue(executeData, forKey: sceneId)
            if let uuid = meshUUID {
                SceneExecuteData.save(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId), sceneData: executeData)
            }
            
        case is SceneDelete:
            let sceneId = (message as! SceneDelete).scene
            self.sceneDatas.removeValue(forKey: sceneId)
            if let uuid = meshUUID {
                SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId))
                
                // 组对应场景数据是否待删除
                if let scene = MeshNetworkManager.instance.scenes.first(where: {$0.number == sceneId}), let group = self.group, let groupSceneData = group.info.bindSceneDatas[sceneId], groupSceneData.state == .waitDelete {
                    // 组内设备已删除对应场景缓存
                    if !group.nodes.contains(where: { $0.sceneDatas[sceneId] != nil }) {
                        group.info.bindSceneDatas.removeValue(forKey: sceneId)
                        // 设备加入组，组加入场景，场景加入日程 Node->Group->Scene->Schedule
                        // 场景加入日程后关联场景的组也加入日程，场景移出组后吧组间接关联的日程删除
                        group.info.bindSchedules.removeAll(where: { groupSchedule in scene.info.bindSchedules.contains(where: { $0.id == groupSchedule.id }) })
                        // 删除组对应的场景数据缓存
                        scene.info.groups.removeAll(where: { $0.address.address == group.address.address })
                        SceneExecuteData.deleteData(meshUUID: uuid, address: group.address.address, sceneId: Int(sceneId))
                        
                    }
                }
            }
           
        case is SchedulerActionSet:
            let actionMessage = (message as! SchedulerActionSet)
            if actionMessage.entry.isValid {
                self.scheduleDatas.updateValue(actionMessage.entry, forKey: Int(actionMessage.index))
                if let uuid = meshUUID {
                    Node.saveSchedule(meshUUID: uuid, address: primaryUnicastAddress, scheduleId: Int(actionMessage.index), entry: actionMessage.entry)
                }
            }else {
                self.scheduleDatas.removeValue(forKey: Int(actionMessage.index))
                if let uuid = meshUUID {
                    Node.deleteSchedule(meshUUID: uuid, address: primaryUnicastAddress, scheduleId: Int(actionMessage.index))
                    
                    // 对应日程删除设备/组
                    if let schedule = MeshNetworkManager.instance.schedules.first(where: {$0.id == actionMessage.index}) {

                        // 设备已加入组，并且组内没有设备缓存对应日程数据，则直接让日程删除该组缓存
                        var isSaveSchedule = false
                        // 判断组是否因为此设备而无法从日程中删除，设备删除后组也从日程中删除
                        if let group = schedule.needDeleteGroups.first(where: { $0.nodes.contains(self) }), !group.nodes.contains(where: { $0.scheduleDatas[schedule.id] != nil }) {
                            schedule.needDeleteGroups.removeAll(where: { $0.address.address == group.address.address })
                            group.info.bindSchedules.removeAll(where: { $0.id == schedule.id })
                            
                            isSaveSchedule = true
                        }
                        // 判断场景是否因为此设备无法从日程中删除，设备删除后场景也从日程中删除
                        if let scene = schedule.needDeleteScenes.first(where: { $0.info.groups.contains(where: { $0.nodes.contains(self) }) }), !scene.info.groups.contains(where: { $0.nodes.contains(where: { $0.scheduleDatas[schedule.id] != nil }) }) {
                            schedule.needDeleteScenes.removeAll(where: { $0.number == scene.number })
                            isSaveSchedule = true
                        }
                        
                        if schedule.needDeleteNodes.contains(self) {
                            schedule.needDeleteNodes.removeAll(where: { $0.primaryUnicastAddress == self.primaryUnicastAddress })
                            isSaveSchedule = true
                        }
                        if isSaveSchedule {
                            schedule.save(meshUUID: uuid)
                        }
                    }
                    
                }
                
            }
        
        default:
            break
        }
        
        
    }
    
}

/// 同步数据
struct SyncData {
    /// 设备是否需要订阅/加入组（订阅信息不完整）
    var subscribeGroup: Bool = false
    /// 设备是否需要退出组
    var unsubscribeGroup: Bool = false
    /// 设备需要同步的场景数据list
    var syncScenes: [SceneNumber : SceneExecuteData] = [:]
    /// 设备需要同步的日程list
    var syncSchedules: [Schedule] = []
    /// 设备待删除的场景数据list
    var deleteScenes: [Scene] = []
    /// 设备待删除的日程list
    var deleteSchedules: [Schedule] = []
    /// 是否不需要同步
    func isEmpty() -> Bool {
        return !(subscribeGroup || unsubscribeGroup || syncScenes.count > 0 || syncSchedules.count > 0 || deleteScenes.count > 0 || deleteSchedules.count > 0)
    }
}

extension SchedulerRegistryEntry {
    /// 是否开启
    var isEnabled: Bool {
        return self.action != .noAction && self.month.value > 0
    }
    
    /// 是否有效
    var isValid: Bool {
        return self.action != .noAction
    }
    
    static func == (lhs: SchedulerRegistryEntry, rhs: SchedulerRegistryEntry) -> Bool {
        return lhs.year.value == rhs.year.value && lhs.month.value == rhs.month.value && lhs.day.value == rhs.day.value && lhs.hour.value == rhs.hour.value && lhs.minute.value == rhs.minute.value && lhs.second.value == rhs.second.value && lhs.dayOfWeek.value == rhs.dayOfWeek.value && lhs.action == rhs.action && lhs.transitionTime.rawValue == rhs.transitionTime.rawValue && lhs.sceneNumber == rhs.sceneNumber
    }
}
