# HDB Smart Hub Interface Control Document

> AI-readable Markdown conversion of **SLP Interface Control Document.pdf**. Document designation: **Tender Amendment No.2**. This is a transcription and structural conversion of the supplied document, not a revised protocol specification.

## 转换说明 / Conversion notes

- **Source:** `SLP Interface Control Document.pdf`, 67 pages. PDF creation/modification metadata: `2021-11-16 20:29:33 +08:00`; this is file metadata, not an inferred protocol revision date.
- **Converted:** 2026-10-20. Source SHA-256: `fb099dfab9afd46a8bc89da49d62eb87a535c916dbfa78262a8abd5bb4aca037`.
- **Language:** original English preserved; conversion guidance is separate from source requirements.
- **Coverage:** sections 1–6 and Appendices I–III; source headings, protocol tables, examples, units, ranges, remarks and page references are retained. Repeated page headers/footers and layout-only line breaks are removed.
- **Tables:** merged cells are expanded; compatible cross-page tables/rows are joined. Every source table row has a `Source PDF page` column. Empty cells remain empty; no defaults or required/optional status are inferred from blanks.
- **Examples:** 21 block examples are formatted as parseable JSON. Typographic double quotes are converted to ASCII, trailing commas are removed, and `"Parameters": {...}` fragments are enclosed in an outer object. Three missing commas after `DimLevel` in the p. 40–41 dimming examples are inserted. Keys, values, types and meaningful string whitespace are preserved; these formatting repairs do not resolve the source inconsistencies listed below. Original visual bolding is not retained; mandatory-field definitions remain explicit in their respective sections.
- **Figures:** transmission, command-flow, proximity, predictive and daylight-band diagrams are transcribed into text/tables. MQTTfx screenshots are described with relevant visible settings; incidental local paths, generated client IDs, screenshot payloads and log records are not reproduced byte for byte. There are no companion-image dependencies.
- **Embedded spreadsheet:** p. 62 shows `Master Data 20210801 Template.xlsx`; the icon is not treated as the spreadsheet contents. The visible master-data tables are included.
- **Traceability:** `pdf-page-N` anchors and source-page comments refer to PDF page numbers. A cross-page table is positioned at its first page; use the per-row page column for exact provenance.
- **Deletion marks corrected (2026-10-20):** visual inspection of PDF pages 30 and 38 confirms that ~~Unoccupy_Off~~ and its page-30 explanation are struck through in the source. The Markdown now preserves these deletion marks; this value is not an active enumeration member.

## App 项目约定 / App-specific decisions

以下为 2026-10-20 用户明确确认的 App 行为，不改写下面保留的 PDF 原文：

- `setLightInstallDate` 在 App 中支持 Unicast、Multicast、Broadcast 三种目标范围；Multicast 是本项目扩展，原 PDF 第 30 页仍写明仅 Unicast / Broadcast。
- `FailsafeDelay` 与 `InstallDate` 只保存到 `hdb` JSON，不向设备发送对应 Mesh 参数。
- Lighting Configuration 选择 Multicast 时，实际使用 Lighting Zone 的 Mesh groupAddress 组播。该命令的全部消息发送成功后，App 按全部目标成功更新 `hdb`，不等待逐设备 ACK；这是 App 成功策略，不是 PDF 对逐设备结果的保证。
- Broadcast 优先使用实际可覆盖目标模型的广播路径；各命令的 element 限制及必要补发见[当前设计](../../docs/261020_1649_HDB_lighting_configuration_design.md)。

## 原文差异与待确认项 / Source ambiguities

The following are conversion observations, not amended requirements. Do not silently choose one spelling, value or rule when implementing from this document.

| Item | Original evidence | Source PDF pages |
| --- | --- | --- |
| Rain reading field | Data dictionary: `RainValue`; event design: `RainfallValue`. Both are preserved. | 14–15 |
| Allowed parameter types | General definitions say only String and Number; `BinData` is Array, and configuration examples use arrays of objects. | 7, 14, 24, 26–28, 36–55 |
| EventType maximum length | General tables specify 31 bytes; several defined command names, such as `SmartLighting/setDaylightHarvestingProfile`, exceed that length. | 6, 23, 49 |
| Override command spelling | A mandatory-field sample uses `SmartLighting/setLightingOverride`; command definitions and JSON use `SmartLighting/setLightOverride`. | 23, 19–21, 29 |
| Sensor status | General definition: `online, offline, error, warning`, length 10; lighting dictionary: `online, offline, error`, length 20. | 6, 13 |
| Battery voltage example | Permitted range is `3.6 to 12`, but sample value is `3.5`. | 15, 56 |
| Fault-code example | Range is `SH-LS-OE-[106301-106400]`, while the sample is `SH-LS-OE-106001`. Alarm rows use 106301–106305. | 15–16 |
| Emergency-test dates | Dictionary uses `dd-MM-yyyy`; JSON contains `01-15-2020` and `02-15-2020`, which do not match that format. | 54–56 |
| Case and spacing | `Charger_Fault` versus `Charger_fault`; response table uses `Test Time` while dictionaries use `TestTime`; a dictionary prints `RepeatActivation,` with a trailing comma. | 15, 50, 53, 56 |
| Initial event sample identifiers | p. 4 includes leading spaces in SenderId/SensorId and an internal space in SensorId. The first example retains these source values. | 4 |
| MQTTfx example QoS | Publish screenshot selects QoS 0; protocol text proposes QoS 2. Screenshot values are illustrative. | 10–12 |
| Nomenclature examples | `PCFDMS` and `PCDFMS` both occur. Appendix II also retains `Longtitude`, a latitude description for that row, and sample location separators differing from the naming syntax. | 62–65 |
| Water-meter example limits | Appendix II lists maximum flow `3 L/hr` and minimum flow `3125 L/hr`; the apparent inconsistency is preserved. | 64 |
| Daylight-band boundaries | The diagram provides four lux boundaries but does not specify equality handling at a boundary. | 51 |

## Navigation

| Section | Source PDF starting page |
| --- | --- |
| [1 INTRODUCTION](#section-1) | 1 |
| [1.1 Purpose](#section-1-1) | 1 |
| [1.2 Scope](#section-1-2) | 1 |
| [1.3 Definitions and Terms](#section-1-3) | 1 |
| [2 SYSTEM OVERVIEW](#section-2) | 2 |
| [2.1 Modes of Data Transmission](#section-2-1) | 2 |
| [2.2 Connectivity Mode](#section-2-2) | 3 |
| [3 INTERFACE REQUIREMENTS](#section-3) | 4 |
| [3.1 Interface Overview](#section-3-1) | 4 |
| [3.2 Protocol Allocation based on the sensor type](#section-3-2) | 4 |
| [3.3 Sensor Integration using MQTT protocol in detail](#section-3-3) | 4 |
| [3.3.1 Mandatory Field Definition for Events](#section-3-3-1) | 5 |
| [3.3.2 Mandatory field definition for alarms on top of events fields](#section-3-3-2) | 9 |
| [3.3.3 Security Requirements](#section-3-3-3) | 10 |
| [3.3.4 MQTT Structure and Protocol settings](#section-3-3-4) | 10 |
| [3.3.5 Testing using MQTTfx (or equivalent)](#section-3-3-5) | 11 |
| [4 INTERFACE DEFINITIONS IN DETAIL](#section-4) | 13 |
| [4.1 Smart Lighting](#section-4-1) | 13 |
| [4.1.1 Smart Lighting Events and Alarms](#section-4-1-1) | 13 |
| [4.1.1.1 Data Dictionary](#section-4-1-1-1) | 13 |
| [4.1.1.2 Event Design](#section-4-1-1-2) | 15 |
| [4.1.1.3 Alarm Design](#section-4-1-1-3) | 15 |
| [4.1.2 Smart Lighting Configuration and Control](#section-4-1-2) | 16 |
| [4.1.2.1 Interface Overview](#section-4-1-2-1) | 16 |
| [4.1.2.2 System Integration using MQTT Protocol](#section-4-1-2-2) | 16 |
| [4.1.2.2.1 Mandatory Field Definition for Events(Smart Lighting)](#section-4-1-2-2-1) | 22 |
| [4.1.2.2.2 MQTT Structure and Protocol settings](#section-4-1-2-2-2) | 24 |
| [4.1.2.3 Interface Definitions in Detail](#section-4-1-2-3) | 25 |
| [4.1.2.3.1 Lighting Zones](#section-4-1-2-3-1) | 25 |
| [4.1.2.3.2 Trigger Zones](#section-4-1-2-3-2) | 27 |
| [4.1.2.3.3 Lighting Configuration](#section-4-1-2-3-3) | 29 |
| [4.1.2.3.4 Sensor Configuration](#section-4-1-2-3-4) | 31 |
| [4.1.2.3.5 Proximity Lighting](#section-4-1-2-3-5) | 32 |
| [4.1.2.3.6 Predictive Lighting](#section-4-1-2-3-6) | 33 |
| [4.1.2.3.7 Timer Profiles](#section-4-1-2-3-7) | 35 |
| [4.1.2.3.8 Dimming Profiles](#section-4-1-2-3-8) | 38 |
| [4.1.2.3.9 Luminance Profiles](#section-4-1-2-3-9) | 42 |
| [4.1.2.3.10 Daylight Profile](#section-4-1-2-3-10) | 46 |
| [4.1.2.3.11 Rain Profile](#section-4-1-2-3-11) | 47 |
| [4.1.2.3.12 Daylight Harvesting Profile](#section-4-1-2-3-12) | 49 |
| [4.1.2.3.13 Normal Light Automatics Test](#section-4-1-2-3-13) | 51 |
| [4.1.2.3.14 Emergency Light Automatics Test](#section-4-1-2-3-14) | 52 |
| [5 POINTS TO BE NOTED](#section-5) | 57 |
| [6 MASTER DATA CONFIGURATION](#section-6) | 58 |
| [6.1 Master device list and properties (descriptive index label)](#section-6-1) | 58 |
| [6.2 Sensor Details for Smart Hub](#section-6-2) | 58 |
| [6.3 Master Data Considerations](#section-6-3) | 60 |
| [Appendix I – Glossary of Terms](#section-appendix-i) | 61 |
| [Appendix II– Masterdata Attributes Sample](#section-appendix-ii) | 62 |
| [Appendix III – Nomenclature for Sensor Naming and Masterdata](#section-appendix-iii) | 65 |

---

<a id="pdf-page-1"></a>

<!-- Source PDF page 1 -->

<a id="section-1"></a>

## 1 INTRODUCTION

<a id="section-1-1"></a>

### 1.1 Purpose

The purpose of this Interface Control Document (ICD) is to define the interface scope, data parameters and demarcation between the SLP/DECADA/Smart Hub and Smart Systems (SLS) to be ingested. It documents and tracks the necessary information required to effectively define the SLP/DECADA/Smart Hub system’s interface as well as any rules for communicating with it.

<a id="section-1-2"></a>

### 1.2 Scope

This document covers all the interface requirements between the SLP/DECADA/Smart Hub and Smart Systems (SLS). This ICD helps to ensure compatibility between system segments and components by clearly communicating all possible inputs and outputs between the components.

<a id="section-1-3"></a>

### 1.3 Definitions and Terms

The Interface Control Document uses a few special terms like event and alarms. Events are operator actions, informational messages, tracking/auditing messages and statistical readings. When Smart Hub receives these events, it processes them based on the rules set and the event becomes an alarm if the event follows the rule.

<a id="pdf-page-2"></a>

<!-- Source PDF page 2 -->

**Figure transcription (PDF p. 2):** Mode 1: Sensors → Sensor Vendor → HDB.

<a id="section-2"></a>

## 2 SYSTEM OVERVIEW

This ICD describes the relationship between the Smart Systems (SLS) and SLP/DECADA/Smart Hub on data ingestion aspects. This ICD specifies the interface requirements the participating systems must meet. It describes the concept of operations for the interface, defines the message structure and protocols that govern the interchange of data, and identifies the communication paths along which the project team expects data to flow. For each interface, the ICD provides the following information:

- A description of the data exchange format and protocol for exchange

- A general description of the interface

- Assumptions where appropriate

- Estimated size and frequency of data exchange

- Mandatory Security Standard

<a id="section-2-1"></a>

### 2.1 Modes of Data Transmission

Systems are to transmit data through the following three modes:

| Mode | Description | Source PDF page |
| --- | --- | --- |
| 1 | Sensors are first connected to a vendor system/server, which would then send data to Smart Hub. | 2 |
| 2 | Sensors send data to vendor system/servers and Smart Hub simultaneously through two separate data links. (For selected sensors only) | 3 |
| 3 | Sensors only send data only to SLP/DECADA/Smart Hub. | 3 |

<a id="pdf-page-3"></a>

<!-- Source PDF page 3 -->

**Figure transcription (PDF p. 3):** Mode 2: Sensors → Sensor Vendor and Sensors → HDB over two separate links. Mode 3: Sensors → HDB directly.

<a id="section-2-2"></a>

### 2.2 Connectivity Mode

The Contractor and the respective Specialist of the Smart System(s) shall adopt the following connectivity modes for the Systems:

| No. | Smart System | Mode | Source PDF page |
| --- | --- | --- | --- |
| 1 | Smart Lighting System | 3 | 3 |

<a id="pdf-page-4"></a>

<!-- Source PDF page 4 -->

<a id="section-3"></a>

## 3 INTERFACE REQUIREMENTS

<a id="section-3-1"></a>

### 3.1 Interface Overview

Smart Hub provides MQTT as the interface method for data ingestion.

- Smart Hub sensor integration using MQTT protocol are divided into few steps:

- Framework design (Data Dictionary, Event & Alarm Design)

- Asset loading (Master Data)

- System configurations for alarms (Smart Hub admin task)

- Client cert generation

- Sending live sensor data over MQTT protocol

<a id="section-3-2"></a>

### 3.2 Protocol Allocation based on the sensor type

All Smart Systems shall use MQTT interface to transmit data to Smart Hub. All on-site sensors for mode 1 data transmission shall also transmit in MQTT (to the vendor system/server).

<a id="section-3-3"></a>

### 3.3 Sensor Integration using MQTT protocol in detail

MQTT protocol specification details are available in

http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html

Payload format is in JavaScript Object Notation (JSON) with some mandatory key value pairs.

Sample payload:

<!-- Example source PDF pages: 4, 5; formatting normalized -->

```json
{
  "SenderId": " SmartLighting-600209-01",
  "SensorId": " SmartLighting-ST-600209- 01010201",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01010215-20160712104950272",
  "EventType": "SmartLighting/motion#reading",
  "Parameters": {
    "sensorstatus": "online",
    "Time": "2016-07-12 10:49:50.272",
    "Severity": 6,
    "MotionCount": 10
  }
}
```

<a id="pdf-page-5"></a>

<!-- Source PDF page 5, continued example above -->

Highlighted in bold are mandatory fields/keys for successful communication with Smart Hub. The values for the mandatory fields/keys are explained below in detail. The non-mandatory fields/keys are designed based on the sensor type and based on how the user wants to see the information from the sensors.

<a id="section-3-3-1"></a>

#### 3.3.1 Mandatory Field Definition for Events

| Field Name | Description | Sample Value | Length in Byte | Source PDF page |
| --- | --- | --- | --- | --- |
| SenderId | SenderID refers to the sender of the data. Depending on the design of the Smart System, this can be the aggregation point of the data, location of the System, or the sensor itself. &lt;SensorType&gt;-&lt;PostalCode&gt;-&lt;AggregatorIdentifier&gt; Sensor Type must be alphabets without special characters; Instead of Postal code, location code can be used if there is no postal code available for the location. Eg. JE-OUTDOOR | Refer to table in Appendix III | 255 | 5 |
| SensorId | &lt;SensorType&gt;-&lt;Vendor&gt;-&lt;PostalCode&gt;-&lt;GenericIdentifier&gt; Vendor name must be alphanumeric without special characters; Instead of Postal code, location code can be used if there is no postal code available for the location. E.g. JE-OUTDOOR A generic Identifier is used so that even when the specific sensor is replaced by new hardware, Smart Hub recognises it as the same sensor point. | Refer to table in Appendix III | 255 | 6 |
| Resourcepath | Resource path is the postal code of the block or the location code. This value should be same as the postal code used in the master data while loading sensor details. If postal code is not available for some sensors, then location code can be used. E.g. JE-OUTDOOR | 600226 | 255 | 6 |
| EventId | Reference/transaction Id. Used to group few events together. EV-&lt;PostalCode&gt;-&lt;SerialNo&gt;-&lt;Timestamp&gt; | EV-600216-01010215-20160712104950272 | 255 | 6 |
| EventType | Format is &lt;SensorType&gt;/&lt;sub-component&gt; #&lt;Type of event&gt; This is further defined below. | E.g. SmartLighting/motion#reading | 31 | 6 |
| sensorstatus | To indicate sensor status List of status are online, offline, error, warning | online | 10 | 6 |

<a id="pdf-page-6"></a>

<!-- Source PDF page 6 -->

<a id="pdf-page-7"></a>

<!-- Source PDF page 7 -->

| Field Name | Description / Severity Code | Severity Name | Severity Meaning | Sample Value | Length in Byte | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- |
| Time | yyyy-MM-dd HH:mm:ss.SSS yyyy - Year MM - Month dd - Day HH - Hour 24hr format mm - Minute ss - Second SSS - Millisecond |  |  | 2016-07-12 10:49:50.272 | 25 | 7 |
| Severity | 1 | Critical | A situation where the System is unable to operate (e.g. SmartIrrigation/moisturesensor#equipmentfault) | e.g. 3 | 255 | 7 |
| Severity | 2 | Major | Where there is a fault in some of the important equipment but it does not affect the entire operation of the System. |  |  | 7 |
| Severity | 3 | Minor | Minor equipment fault. |  |  | 7 |
| Severity | 4 | Info | It may not be an alarm but the user may be interested to know. |  |  | 7 |
| Severity | 5 | Clear | When fault is cleared. |  |  | 7 |
| Severity | 6 | Reading | While updating the system status. |  |  | 7 |
| Parameters | All the sensor related fields are to be enclosed in the parameters. It supports only two data types --String and Number. String values are enclosed in double quotation marks, whereas numbers are not enclosed in quotation marks. |  |  | {"LightStatus":"Normal"} | Key:255 Value:255 | 7 |

Events such as SmartLighting/motion#reading, etc are for the updating of System status and hence the severity for such cases is ‘Reading’. For the faults, severity depends on the type of the fault.

<a id="pdf-page-8"></a>

<!-- Source PDF page 8 -->

<a id="section-3-3-1-continued"></a>

#### 3.3.1 Mandatory Field Definition for Events (Continued)

**Parameters**

Parameters are the property used to indicate the dynamic values of the sensors. Since each of the sensors has a different set of functionalities, which are dynamic in nature, the current design will allow many different types of combinations of parameters to be sent to Smart Hub. Unit of measurement can also be used along with parameter names for e.g. {“AC_voltage (V)”:230} or {“AC_current (A)”:3.0}

**Event Type**

Event type is used to describe what type of event it belongs to. It is used to visualize event on the operator’s console. The strategy for creating the event types are:

Event Type = `<Type of Sensor>` / `<sub-type>` #`<event type>` E.g.: SmartLighting/motion#reading SmartLock/Controller#intrusion Where #reading are status updates or heart beat events (e.g. routine readings). The frequency of the heart beat / status update is defined according to the sensor type.

<a id="pdf-page-9"></a>

<!-- Source PDF page 9 -->

<a id="section-3-3-2"></a>

#### 3.3.2 Mandatory field definition for alarms on top of events fields

| Field Name | Description | Data Type | Source PDF page |
| --- | --- | --- | --- |
| Faultcode | Specifies type of fault as defined in the System specific dictionary | String | 9 |
| Description | Description or note of the fault/incident | String | 9 |

Faults in the Smart Systems shall be identified and assigned severity values based on the priority of the fault. For example, if a certain event type is identified as an alarm, the alarm can be configured in the Smart Hub system configuration page (hdb->cep_config->severity.events) to get this event to appear as an alarm. Thereafter, the Smart Hub system will detect the alarms based on the severity and alarm types configured. These additional fields help to visualize the details of the alarm. In order to clear a fault, the sensor system has to send another event to clear the previous fault generated in the same system.

| Field | Description | Data Type | Source PDF page |
| --- | --- | --- | --- |
| RefEventId | Specifies the previous fault event id | String | 9 |
| RefEventType | Specifies the previous fault event type | String | 9 |

<a id="pdf-page-10"></a>

<!-- Source PDF page 10 -->

<a id="section-3-3-3"></a>

#### 3.3.3 Security Requirements

MQTT Broker supports only TLS 1.2 protocol. Supported cipher suits are:

- TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,

- TLS_DHE_RSA_WITH_AES_256_GCM_SHA384,

- TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,

- TLS_DHE_RSA_WITH_AES_256_CBC_SHA256,

- TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,

- TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 The SSL client certificates will be issued to each of the vendor, and the sensor/system has to use this certificate to authenticate itself to the broker.

<a id="section-3-3-4"></a>

#### 3.3.4 MQTT Structure and Protocol settings

Broker URL is:

Production: ssl://192.168.8.35:9884

UAT: ssl://192.168.8.38:9884

Topic name will be based on the sensor type. Format for topic is VirtualTopic/mqtt/`<sensor type>`/incoming Proposed Quality of Services setting, Qos 2: Exactly once delivery This is the highest quality of service, for use when neither loss nor duplication of messages are acceptable. There is an increased overhead associated with this quality of service. A QoS 2 message has a Packet Identifier in its variable header. The receiver of a QoS 2 PUBLISH Packet acknowledges receipt with a two-step acknowledgement process. Keep live timeout for message is 60 seconds for MQTT broker to retain the established session. Heartbeat rate frequency for every sensor is by default 15 minutes, i.e. In order for the sensor to appear as online in Smart Hub, they sensor must send an event message every 15 minutes.

<a id="pdf-page-11"></a>

<!-- Source PDF page 11 -->

**Screenshot transcription (PDF p. 11; illustrative MQTTfx settings):**

| Setting | Visible value |
| --- | --- |
| Profile Name | smarthub-mqtt-prod |
| Profile Type | MQTT Broker |
| Broker Address | 192.168.8.35 |
| Broker Port | 9884 |
| Client ID | Generated by MQTTfx; regenerate for the client |
| Connection Timeout | 30 |
| Keep Alive Interval | 60 |
| Clean Session | Checked |
| Enable SSL/TLS | Checked |
| Protocol | TLSv1.2 |
| Certificate option | Self signed certificates |
| CA File / Client Certificate File / Client Key File | Local PEM file paths are shown as examples; HDB provides the files |
| Client Key Password | Empty in the screenshot |
| PEM Formatted | Checked |

The screenshot's local Windows paths and generated client ID are illustrative UI values; they are not transcribed as configuration requirements.

<a id="section-3-3-5"></a>

#### 3.3.5 Testing using MQTTfx (or equivalent)

MQTTfx is an example of a free Graphical User Interface (GUI) testing tool, which helps to generate MQTT messages and send to the Smart Hub for testing. Download MQTTfx from http://www.jensd.de/apps/mqttfx/1.7.0 Settings needed:

<a id="pdf-page-12"></a>

<!-- Source PDF page 12 -->

**Screenshot transcription (PDF p. 12):** MQTTfx shows a connected session (green status indicator), Publish / Subscribe / Scripts / Broker Status / Log tabs, topic selection, a JSON payload editor, QoS choices and a Publish button. The example topic is `VirtualTopic/mqtt/waterpump/incoming`; the sample uses a water-pump emergency alarm, not a SmartLighting command. The selected UI QoS is 0, while section 3.3.4 proposes QoS 2. The second screenshot shows connection/publish logs and the transmitted payload. Screenshot log entries and illustrative water-pump payload values are not reproduced byte for byte.

Notes:

Client Id has to be regenerated by MQTTfx; Certificate Authority (CA) file, client certificate, client key shall be provided by HDB. Steps for publishing message to MQTT broker:

- Select the server you want to connect.

- Connect and wait for green icon to appear on the right most corner

- Create sample payload and choose topic

- Publish the message

- Browse logs tab for logs

<a id="pdf-page-13"></a>

<!-- Source PDF page 13 -->

<a id="section-4"></a>

## 4 INTERFACE DEFINITIONS IN DETAIL

The following section describes the interface definition for each sensor type in detail. In general:

The measurements readings and status changes are Events. Faults and abnormal conditions are Alarms. The alarm is triggered based on the rules set in Smart Hub. One of the rules set is that the Smart Hub will trigger an alarm based on the severity of an event. e.g. If severity < 4, an event turns to alarm.

<a id="section-4-1"></a>

### 4.1 Smart Lighting

<a id="section-4-1-1"></a>

#### 4.1.1 Smart Lighting Events and Alarms

<a id="section-4-1-1-1"></a>

##### 4.1.1.1 Data Dictionary

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Time | Time | String | 25 |  | 2016-11-24 14:52:50.276 | SGT | 13 |
| Severity | Severity | Number | 8 | 1-6 | 6 |  | 13 |
| sensorstatus | Sensor status | String | 20 | online, offline, error | online |  | 13 |
| GatewayStatus | Health status of gateway | String | 20 | Online / Offline | Online |  | 13 |
| LightStatus | Health status of light | String | 20 | Normal /Dim /Flicker /Dim_Flicker Off | Normal |  | 13 |
| SensorHealthStatus | Health status of sensor | String | 20 | Normal /Not_Working | Normal |  | 13 |
| NetworkStatus | Network status of sensor | String | 20 | Online / Offline | Online |  | 13 |
| ELightStatus | Health status of emergency light | String | 25 | Normal /Not_Responding /Emergency_Mode /Battery_Out /Battery_Low | Normal |  | 13 |
| MotionCount | Motion detection count | Number | 10 |  | 10 | Number of motion detections per update interval Motion detection count is the sum of all the bins that are with motion within the update interval. | 13 |
| BinStartTime | Start time of motion bins | String | 25 |  | 2016-11-24 14:52:50.276 |  | 13 |
| BinCount | Number of motion bins per update interval | Number | 10 |  | 90 | Divide update interval into multiple bins, each bin is 10 sec | 14 |
| BinData | Data of motion bins per update interval | Array | 20 |  | [128, 240, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] | Motion bins per update interval are arranged in groups of bins in ascending order of time. Each group consists of 8 bins (one byte) and the most significant bit is the first bin and so on. Individual bin is set to 1 if motion is detected within the respective bin period. | 14 |
| DaylightValue | Photo sensor value | Number | 10 |  | 2000 | Value is in lux | 14 |
| TemperatureValue | Temperature sensor value | Number | 10 |  | 28 | Value is in Celsius | 14 |
| HumidityValue | Humidity sensor value | Number | 10 |  | 60 | Value is in relative humidity % RH | 14 |
| RainValue | Rain sensor value | Number | 10 |  | 50 | Value is in mm/Hour | 14 |
| EnergyUsage | Cumulative power consumption per luminaire | Number | 10 |  | 1000 | Value is in kWh | 14 |
| LightUsage | Cumulative burn time per luminaire | Number | 10 |  | 100 | Value is in hours | 14 |
| PowerValue | Power consumption under light full on condition | Number | 10 |  | 300 | Wh or any other value that is related to light power consumption | 14 |
| BlinkValue | Blink intensity under light full on condition | Number | 10 |  | 100 | Percent flicker, flicker index or any other value that is related to light blinking | 14 |
| TestTime | Date and time of emergency light test | String | 25 |  | 2016-11-24 14:52:50.276 |  | 14 |
| TestType | Test type for emergency light | String | 25 | Functional /Duration /Commissioning | Functional |  | 14 |
| TestResult | Test result for emergency light | String | 25 | Passed /Failed /Not_Tested /Test_In_Progress /Result_Not_Available | Passed |  | 14 |
| FailureType | Type of failure for emergency light | String | 25 | Light_Fail /Battery_Fail /Charger_Fail / Light_Dim /Light_Flicker /Light_Dim_Flicker | Battery_Fail | For test failed case | 14,15 |
| NotTested | Reason for not tested for emergency light | String | 50 | Not_Responding /Emergency_Mode /Test_Button_Pressed /Light_Power_Not_Calibrated /Battery_Below_Nominal_Voltage /Battery_Not_Fully_Charged /Battery_Removed /Switch_Over_Fail /Incorrect_Nominal_Battery_Voltage /Battery_Low /Charger_Fault | Battery_Removed | For not tested case | 15 |
| BatteryVoltage | Battery voltage after lighting test for emergency light | Number | 10 | 3.6 to 12 | 3.5 | Value is in voltage | 15 |
| RefEventType | Only for clearing early alarm | String | 32 |  |  |  | 15 |
| RefEventId | Only for clearing early alarm | String | 32 |  |  |  | 15 |
| Description | Description about the fault | String | 512 |  |  |  | 15 |
| Faultcode | Fault code | String | 32 | SH-LS-OE- [106301-106400] | SH-LS-OE-106001 |  | 15 |

<a id="pdf-page-14"></a>

<!-- Source PDF page 14 -->

<a id="pdf-page-15"></a>

<!-- Source PDF page 15 -->

<a id="section-4-1-1-2"></a>

##### 4.1.1.2 Event Design

| Event Type | Fields | Severity | Frequency (mins) | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/motion#reading | sensorstatus, Time, Severity, MotionCount, BinStartTime, BinCount, BinData | 6 | 15 | 15 |
| SmartLighting/daylight#reading | sensorstatus, Time, Severity, DaylightValue | 6 | 15 | 15 |
| SmartLighting/temperature#reading | sensorstatus, Time, Severity, TemperatureValue | 6 | 15 | 15 |
| SmartLighting/humidity#reading | sensorstatus, Time, Severity, HumidityValue | 6 | 15 | 15 |
| SmartLighting/rain#reading | sensorstatus, Time, Severity, RainfallValue | 6 | 15 | 15 |
| SmartLighting/energyusage#reading | sensorstatus, Time, Severity, EnergyUsage | 6 | Once a day | 15 |
| SmartLighting/lightusage#reading | sensorstatus, Time, Severity, LightUsage | 6 | Once a day | 15 |
| SmartLighting/powervalue#reading | sensorstatus, Time, Severity, PowerValue, BlinkValue | 6 | Once a day | 15 |
| SmartLighting/elightresult#reading | sensorstatus, Time, Severity, TestTime, TestType, TestResult, FailureType, NotTested, BatteryVoltage | 6 | Ad hoc basis | 15 |

<a id="section-4-1-1-3"></a>

##### 4.1.1.3 Alarm Design

<a id="pdf-page-16"></a>

<!-- Source PDF page 16 -->

| Alarm Type | Fields | Severity | FaultCode | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- |
| SmartLighting/gateway#fault | sensorstatus, Time, Severity, Description, Faultcode, GatewayStatus | 1 | SH-LS-OE-106301 |  | 16 |
| SmartLighting/light#fault | sensorstatus, Time, Severity, Description, Faultcode, LightStatus | 3 | SH-LS-OE-106302 |  | 16 |
| SmartLighting/sensor#fault | sensorstatus, Time, Severity, Description, Faultcode, SensorHealthStatus | 3 | SH-LS-OE-106303 |  | 16 |
| SmartLighting/network#fault | sensorstatus, Time, Severity, Description, Faultcode, NetworkStatus | 3 | SH-LS-OE-106304 |  | 16 |
| SmartLighting/elight#fault | sensorstatus, Time, Severity, Description, Faultcode, ELightStatus | 3 | SH-LS-OE-106305 |  | 16 |
| SmartLighting/system#clear | sensorstatus, Time, Severity, Description, SensorId, RefEventId, RefEventType | 5 |  | RefEventId and RefEventType should be the same values as fault EventId and EventType respectively for clearing | 16 |

<a id="section-4-1-2"></a>

#### 4.1.2 Smart Lighting Configuration and Control

<a id="section-4-1-2-1"></a>

##### 4.1.2.1 Interface Overview

Smart Lighting System provides MQTT as the interface method for configuration and control. Integration between Smart Lighting System and HDB Backend System (SLP) using MQTT protocol are divided into few steps:

- Framework design (Data Dictionary, Configuration Design)

- Client cert generation

- Sending set and get command over MQTT protocol

<a id="section-4-1-2-2"></a>

##### 4.1.2.2 System Integration using MQTT Protocol

MQTT protocol specification details are available in

http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html

Payload format is json with some mandatory key value pairs.

<a id="pdf-page-17"></a>

<!-- Source PDF page 17 -->

**Figure transcription (PDF p. 17):** For both Set and Get:

| Direction | Publisher | Broker | Subscriber |
| --- | --- | --- | --- |
| Command | HDB Backend System (SLP) | MQTT Broker (DECADA) | Smart Lighting System |
| Response | Smart Lighting System | MQTT Broker (DECADA) | HDB Backend System (SLP) |

The Set command controls or applies settings to a sensor or a group of sensors. The Get command retrieves settings from a sensor. Get is unicast and selects the sensor by SensorId.

**Set Command**

Set command is used by HDB Backend System (SLP) to control or apply settings to a sensor or a group of sensors. Get command is used to retrieve the settings of a sensor based on sensor ID. It is a unicast command.

<a id="pdf-page-18"></a>

<!-- Source PDF page 18 -->

Sample payload for GET command:

<!-- Example source PDF pages: 18; formatting normalized -->

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-ST-600209-01010215",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01010215-20160822104950234",
  "EventType": "SmartLighting/getLightOverride",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

Sample payload for GET command response:

<!-- Example source PDF pages: 18; formatting normalized -->

```json
{
  "SenderId": "SmartLighting-600209-01",
  "SensorId": "SmartLighting-ST-600209-01010215",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01010215-20160822104950234",
  "EventType": "SmartLighting/getLightOverride",
  "Parameters": {
    "CommandType": "Get_Ack",
    "LightingControl": "Auto"
  }
}
```

**Set Command (Unicast)**

Set command with unicast transmission is used to configure a single sensor based on sensor ID. In this case, configuration zone is not used and shall be set to 0.

Sample payload for unicast SET command:

<a id="pdf-page-19"></a>

<!-- Source PDF page 19 -->

<!-- Example source PDF pages: 19; formatting normalized -->

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-ST-600209-01010215",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01010215-20160822104950234",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "LightingControl": "Auto"
  }
}
```

Sample payload for unicast SET command response:

<!-- Example source PDF pages: 19; formatting normalized -->

```json
{
  "SenderId": "SmartLighting-600209-01",
  "SensorId": "SmartLighting-ST-600209-01010215",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01010215-20160822104950234",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "CommandType": "Set_Ack",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "LightingControl": "Auto"
  }
}
```

**Set Command (Multicast)**

<a id="pdf-page-20"></a>

<!-- Source PDF page 20 -->

Set command with multicast transmission is used to configure a group of sensors under a gateway based on gateway id (sensor id field) and zone id.

Sample payload for multicast SET command:

<!-- Example source PDF pages: 20; formatting normalized -->

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-ST-600209-01000000",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01000000-20160822104950234",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Multicast",
    "ConfigurationZone": 1,
    "LightingControl": "Auto"
  }
}
```

Sample payload for multicast SET command response:

<!-- Example source PDF pages: 20; formatting normalized -->

```json
{
  "SenderId": "SmartLighting-600209-01",
  "SensorId": "SmartLighting-ST-600209-01000000",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01000000-20160822104950234",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "CommandType": "Set_Ack",
    "Transmission": "Multicast",
    "ConfigurationZone": 1,
    "LightingControl": "Auto"
  }
}
```

<a id="pdf-page-21"></a>

<!-- Source PDF page 21 -->

**Set Command (Broadcast)**

Set command with broadcast transmission is used to configure all sensors under a gateway based on gateway id (sensor id field). In this case, configuration zone is not used and shall be set to 0.

Sample payload for broadcast SET command:

<!-- Example source PDF pages: 21; formatting normalized -->

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-ST-600209-01000000",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01000000-20160822104950234",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Broadcast",
    "ConfigurationZone": 0,
    "LightingControl": "Auto"
  }
}
```

Sample payload for broadcast SET command response:

<!-- Example source PDF pages: 21, 22; formatting normalized -->

```json
{
  "SenderId": "SmartLighting-600209-01",
  "SensorId": "SmartLighting-ST-600209-01000000",
  "Resourcepath": 600209,
  "EventId": "EV-600209-01000000-20160822104950234",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "CommandType": "Set_Ack",
    "Transmission": "Broadcast",
    "ConfigurationZone": 0,
    "LightingControl": "Auto"
  }
}
```

<a id="pdf-page-22"></a>

<!-- Source PDF page 22, continued example above -->

Highlighted in bold are mandatory fields/keys for successful communication with HDB Backend System (SLP). The values for the mandatory fields/keys are explained below in detail. The non-mandatory fields/keys are designed based on the parameter type.

<a id="section-4-1-2-2-1"></a>

###### 4.1.2.2.1 Mandatory Field Definition for Events(Smart Lighting)

| Field Name | Description | Sample Value | Length in Byte | Source PDF page |
| --- | --- | --- | --- | --- |
| SenderId | SenderID refers to the sender of the data. Depending on the design of the Smart System, this could be the aggregation point of the data, location of the System, or the sensor itself. &lt;SensorType&gt;-&lt;PostalCode&gt;-&lt;AggregatorIdentifier&gt; System Type must be alphabets without special characters; Instead of Postal code, location code can be used if there is no postal code available for the location. Eg. JE-OUTDOOR Note: Set &lt;SystemType&gt; to “Backend” for command initiated by HDB Backend System (SLP). | Refer to table in Appendix III | 255 | 22 |
| SensorId | &lt;SensorType&gt;-&lt;Vendor&gt;-&lt;PostalCode&gt;-&lt;GenericIdentifier&gt; Vendor name must be alphanumeric without special characters; Instead of Postal code, location code can be used if there is no postal code available for the location. E.g. JE-OUTDOOR A generic Identifier is used so that even when the specific sensor is replaced by new hardware, Smart Hub recognises it as the same sensor point. | Refer to table in Appendix III | 255 | 22 |
| Resourcepath | Resource path is the postal code of the block or the location code. This value should be same as the postal code used in the Master Data while loading sensor details. If postal code is not available, then location code can be used. E.g. JE-OUTDOOR | 600226 | 255 | 23 |
| EventId | Reference/transaction Id. Used to group few events together. EV-&lt;PostalCode&gt;-&lt; GenericIdentifier&gt;-&lt;Timestamp&gt; | EV-600216-01010215-20160712104950272 | 255 | 23 |
| EventType | Format is &lt;SystemType&gt;/&lt;parameter type&gt; | E.g. SmartLighting/setLightingOverride | 31 | 23 |
| CommandType | Indicating set / get request and response: - Set - Set_Ack - Set_Error - Get - Get_Ack - Get_Error Note: Error of set / get command can be due to sensor offline or incorrect parameters. | Set | 20 | 23 |
| Transmission | Indicating transmission type for set command: - Unicast - Multicast - Broadcast Note: - Unicast is for single sensor (select by sensor id). - Multicast is for a group of sensors under a gateway (select by gateway id and configuration zone). - Broadcast is for all sensors under a gateway (select by gateway id). | Unicast | 20 | 23 |
| ConfigurationZone | Indicating lighting zone (1 to 63) to be configured and is meant for multicast command only. For unicast and broadcast command, configuration zone is set to 0. | 1 | 10 | 24 |
| Parameters | All the sensor related fields are to be enclosed in the parameters. It supports only two data types -- String and Number. String values are enclosed in double quotation marks, whereas numbers are not enclosed in quotation marks. | {"LightingControl":"Auto"} | Key:255 Value:255 | 24 |

<a id="pdf-page-23"></a>

<!-- Source PDF page 23 -->

<a id="pdf-page-24"></a>

<!-- Source PDF page 24 -->

**Parameters**

Parameters are the property used to indicate the dynamic values of the sensors. Since each of the sensors has a different set of functionalities, which are dynamic in nature, the current design will allow many different types of combinations of parameters.

**Event Type**

Event type is used to describe what type of event it belongs to. It is used to visualize event on the operator’s console. The strategy for creating the event types are:

Event Type = `<Type of System>`/`<parameter type>` Example:

SmartLighting/setLightOverride

<a id="section-4-1-2-2-2"></a>

###### 4.1.2.2.2 MQTT Structure and Protocol settings

Topic to Publish and Subscribe HDB Backend System Command:

<a id="pdf-page-25"></a>

<!-- Source PDF page 25 -->

HDB Backend System (SLP) publishes to the following topic to send command to a specific smart lighting system based on postal code. The command is defined in the event type.

VirtualTopic/mqtt/SmartLighting/`<postal code>`

HDB Backend System (SLP) subscribes to the following topic to receive command response from smart lighting system. The command response is defined in the event type.

VirtualTopic/mqtt/SmartLighting/response

Smart Lighting System Response:

Smart Lighting System subscribes to the following topic to receive command from HDB Backend System (SLP). The command is defined in the event type.

VirtualTopic/mqtt/SmartLighting/`<postal code>`

Smart Lighting System publishes to the following topic to send command response to HDB Backend System (SLP). The command response is defined in the event type.

VirtualTopic/mqtt/SmartLighting/response

Proposed Quality of Services setting, Qos 2: Exactly once delivery This is the highest quality of service, for use when neither loss nor duplication of messages are acceptable. There is an increased overhead associated with this quality of service. A QoS 2 message has a Packet Identifier in its variable header. The receiver of a QoS 2 PUBLISH Packet acknowledges receipt with a two-step acknowledgement process. Security Requirements:

MQTT Broker supports only TLS 1.2 protocol.

<a id="section-4-1-2-3"></a>

##### 4.1.2.3 Interface Definitions in Detail

<a id="section-4-1-2-3-1"></a>

###### 4.1.2.3.1 Lighting Zones

<a id="pdf-page-26"></a>

<!-- Source PDF page 26 -->

This command is used to assign up to 8 lighting zones to a sensor. Lighting zone consists of a group of sensors and is typically used for device configuration and lighting control (e.g. predictive lighting, dimming profile, etc). Total 63 lighting zones are supported per gateway.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setLightingZone | Set | Transmission, ConfigurationZone, NumberOfZone, ZoneId#1 … ZoneId#n | Assign lighting zones to a sensor (unicast command) | 26 |
| SmartLighting/setLightingZone | Set_Ack | Transmission, ConfigurationZone, NumberOfZone, ZoneId#1 … ZoneId#n |  | 26 |
| SmartLighting/getLightingZone | Get |  | Get settings of lighting zones from a sensor | 26 |
| SmartLighting/getLightingZone | Get_Ack | NumberOfZone, ZoneId#1 … ZoneId#n |  | 26 |

Sample parameters for SET command (SmartLighting/setLightingZone)

<!-- Example source PDF pages: 26; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "NumberOfZone": 2,
    "LightingZones": [
      {
        "ZoneId": 10
      },
      {
        "ZoneId": 15
      }
    ]
  }
}
```

Sample parameters for GET command response (SmartLighting/getLightingZone)

<!-- Example source PDF pages: 26, 27; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Get_Ack",
    "NumberOfZone": 2,
    "LightingZones": [
      {
        "ZoneId": 10
      },
      {
        "ZoneId": 15
      }
    ]
  }
}
```

<a id="pdf-page-27"></a>

<!-- Source PDF page 27, continued example above -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NumberOfZone | Number of lighting zones assigned to a sensor | Number | 10 | 1 to 8 | 5 |  | 27 |
| ZoneId | Lighting zone id | Number | 10 | 1 to 63 | 1 |  | 27 |

<a id="section-4-1-2-3-2"></a>

###### 4.1.2.3.2 Trigger Zones

This command is used to assign up to 8 trigger zones to a sensor. In this case, the sensor is considered as a trigger node and the trigger zones are actually lighting zones being activated by the trigger node. When the sensor detects movement, the lights in the corresponding trigger zones (or lighting zones) will be turned on. Trigger zones are typically used by predictive lighting to turn on lights in multiple paths.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setTriggerZone | Set | Transmission, ConfigurationZone, NumberOfZone, ZoneId#1 … ZoneId#n | Assign trigger zones to a sensor (unicast command to gateway) | 27 |
| SmartLighting/setTriggerZone | Set_Ack | Transmission, ConfigurationZone, NumberOfZone, ZoneId#1 … ZoneId#n |  | 27 |
| SmartLighting/getTriggerZone | Get |  | Get settings of trigger zones from a sensor | 27 |
| SmartLighting/getTriggerZone | Get_Ack | NumberOfZone, ZoneId#1 … ZoneId#n |  | 28 |

<a id="pdf-page-28"></a>

<!-- Source PDF page 28 -->

Sample parameters for SET command (SmartLighting/setTriggerZone)

<!-- Example source PDF pages: 28; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "NumberOfZone": 2,
    "TriggerZones": [
      {
        "ZoneId": 10
      },
      {
        "ZoneId": 15
      }
    ]
  }
}
```

Sample parameters for GET command response (SmartLighting/getTriggerZone)

<!-- Example source PDF pages: 28, 29; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Get_Ack",
    "NumberOfZone": 2,
    "TriggerZones": [
      {
        "ZoneId": 10
      },
      {
        "ZoneId": 15
      }
    ]
  }
}
```

<a id="pdf-page-29"></a>

<!-- Source PDF page 29, continued example above -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NumberOfZone | Number of trigger zones assigned to a sensor | Number | 10 | 1 to 8 | 5 |  | 29 |
| ZoneId | Trigger zone id | Number | 10 | 1 to 63 | 1 |  | 29 |

<a id="section-4-1-2-3-3"></a>

###### 4.1.2.3.3 Lighting Configuration

The following commands are used to configure lighting parameters.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setLightOverride | Set | Transmission, ConfigurationZone, LightingControl, FailsafeDelay | Override light to auto, force on or force off mode | 29 |
| SmartLighting/setLightOverride | Set_Ack | Transmission, ConfigurationZone, LightingControl, FailsafeDelay |  | 29 |
| SmartLighting/getLightOverride | Get |  | Get light override mode | 29 |
| SmartLighting/getLightOverride | Get_Ack | LightingControl, FailsafeDelay |  | 29 |
| SmartLighting/setLightIntensity | Set | Transmission, ConfigurationZone, DimIntensity, BrightIntensity | Set dim and bright intensity | 29 |
| SmartLighting/setLightIntensity | Set_Ack | Transmission, ConfigurationZone, DimIntensity, BrightIntensity |  | 29 |
| SmartLighting/getLightIntensity | Get |  | Get dim and bright intensity | 29 |
| SmartLighting/getLightIntensity | Get_Ack | DimIntensity, BrightIntensity |  | 29 |
| SmartLighting/setSoftDimming | Set | Transmission, ConfigurationZone, RampUpTime, RampDownTime | Set ramp up and ramp down time | 29 |
| SmartLighting/setSoftDimming | Set_Ack | Transmission, ConfigurationZone, RampUpTime, RampDownTime |  | 29 |
| SmartLighting/getSoftDimming | Get |  | Get ramp up and ramp down time | 29 |
| SmartLighting/getSoftDimming | Get_Ack | RampUpTime, RampDownTime |  | 29 |
| SmartLighting/setTimeDelay | Set | Transmission, ConfigurationZone, HoldTime | Set light hold time | 30 |
| SmartLighting/setTimeDelay | Set_Ack | Transmission, ConfigurationZone, HoldTime |  | 30 |
| SmartLighting/getTimeDelay | Get |  | Get light hold time | 30 |
| SmartLighting/getTimeDelay | Get_Ack | HoldTime |  | 30 |
| SmartLighting/setLightInstallDate | Set | Transmission, ConfigurationZone, InstallDate | Set light installed date Only applicable to unicast and broadcast command (unicast command to gateway) | 30 |
| SmartLighting/setLightInstallDate | Set_Ack | Transmission, ConfigurationZone, InstallDate |  | 30 |
| SmartLighting/getLightInstallDate | Get |  | Get light installed date | 30 |
| SmartLighting/getLightInstallDate | Get_Ack | InstallDate |  | 30 |

<a id="pdf-page-30"></a>

<!-- Source PDF page 30 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LightingControl | Set lighting operation mode | String | 20 | Auto /Force_On /Force_Off ~~Unoccupy_Off~~ | Auto | Auto: On-demand lighting based on motion detection. Force_On: Light full on. Force_Off: Light full off. ~~Unoccupy_Off: Turn off light in unoccupy area~~ | 30 |
|  |  |  |  |  |  |  | 30 |
| FailsafeDelay | Delay to enter failsafe mode upon lost sync | Number | 10 | 0 to 250 min | 5 | Set to 0 to enter failsafe mode immediately upon lost sync | 30 |
| DimIntensity | Dim intensity of light | Number | 10 | 0 to 50 | 20 | Value is in percentage | 30 |
| BrightIntensity | Bright intensity of light | Number | 10 | 50 to 100 | 80 | Value is in percentage | 30 |
| RampUpTime | Ramp up time from dim to bright | Number | 10 | 1 to 3 | 1 | Value is in second | 30 |
| RampDownTime | Ramp down time from bright to dim | Number | 10 | 1 to 3 | 2 | Value is in second | 30 |
| HoldTime | Time interval to keep light on upon motion detection | Number | 10 | 10 to 3600 | 30 | Value is in second | 30 |
| InstallDate | Light installed date | String | 20 | dd-MM-yyyy dd - Day MM -Month yyyy - Year | 01-10-2020 |  | 31 |

<a id="pdf-page-31"></a>

<!-- Source PDF page 31 -->

<a id="section-4-1-2-3-4"></a>

###### 4.1.2.3.4 Sensor Configuration

The following commands are used to configure sensor parameters.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setMotionSensitivity | Set | Transmission, ConfigurationZone, MotionSensitivity | Set motion detection range | 31 |
| SmartLighting/setMotionSensitivity | Set_Ack | Transmission, ConfigurationZone, MotionSensitivity |  | 31 |
| SmartLighting/getMotionSensitivity | Get |  | Get motion detection range | 31 |
| SmartLighting/getMotionSensitivity | Get_Ack | MotionSensitivity |  | 31 |
| SmartLighting/setPhotoSensing | Set | Transmission, ConfigurationZone, PhotoSensing, PhotoUpperThreshold, PhotoLowerThreshold | Set threshold values of photo sensor | 31 |
| SmartLighting/setPhotoSensing | Set_Ack | Transmission, ConfigurationZone, PhotoSensing, PhotoUpperThreshold, PhotoLowerThreshold |  | 31 |
| SmartLighting/getPhotoSensing | Get |  | Get threshold values of photo sensor | 31 |
| SmartLighting/getPhotoSensing | Get_Ack | PhotoSensing, PhotoUpperThreshold, PhotoLowerThreshold |  | 31 |
| SmartLighting/setRainSensing | Set | Transmission, ConfigurationZone, RainSensing, RainUpperThreshold, RainLowerThreshold | Set threshold values of rain sensor | 31 |
| SmartLighting/setRainSensing | Set_Ack | Transmission, ConfigurationZone, RainSensing, RainUpperThreshold, RainLowerThreshold |  | 31 |
| SmartLighting/getRainSensing | Get |  | Get threshold values of rain sensor | 31 |
| SmartLighting/getRainSensing | Get_Ack | RainSensing, RainUpperThreshold, RainLowerThreshold |  | 31,32 |

<a id="pdf-page-32"></a>

<!-- Source PDF page 32 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MotionSensitivity | 3 levels of motion detection range | Number | 10 | 1 to 3 | 2 | Level 1 to 3 is corresponding to low, mid and high detection range which may vary according to different sensor types (e.g. indoor / outdoor sensor). | 32 |
| PhotoSensing | Photo sensing control | String | 20 | Enable / Disable | Enable |  | 32 |
| PhotoUpperThreshold | Upper threshold of photo sensor to detect bright daylight | Number | 10 | 50 to 1000 | 400 | Value is in lux | 32 |
| PhotoLowerThreshold | Lower threshold of photo sensor to detect dim daylight | Number | 10 | 50 to 1000 | 200 | Value is in lux | 32 |
| RainSensing | Rain sensing control | String | 20 | Enable / Disable | Enable |  | 32 |
| RainUpperThreshold | Upper threshold of rain sensor to detect heavy rain | Number | 10 | 5 to 255 | 30 | Value is in terms of number of pulses per minute (each pulse is 0.01mm of rainfall) | 32 |
| RainLowerThreshold | Lower threshold of rain sensor to detect light rain | Number | 10 | 5 to 255 | 5 | Value is in terms of number of pulses per minute (each pulse is 0.01mm of rainfall) | 32 |

<a id="section-4-1-2-3-5"></a>

###### 4.1.2.3.5 Proximity Lighting

Proximity lighting is used to turn on lights in advance in a straight path where the pedestrian is heading. This is achieved by listening to the neighbour nodes and turning on light whenever neighbour nodes detect motion. For example, assuming there are 7 sensors in a row which are configured to listen to 2 immediate neighbours. If motion is detected by say sensor 4, which will turn on its own light and lights in sensor 2, 3, 5, and 6 will be tuned on as well by the respective sensors.

<a id="pdf-page-33"></a>

<!-- Source PDF page 33 -->

**Figure transcription (PDF p. 33):** Sensors 1–7 are arranged in a straight line. With two immediate neighbours configured, motion at sensor 4 turns on lights at sensors 2, 3, 4, 5 and 6.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setProximityLighting | Set | Transmission, ConfigurationZone, LightingControl, SaveNodeSetting, NumberOfNeighbourNode | Configure proximity lighting | 33 |
| SmartLighting/setProximityLighting | Set_Ack | Transmission, ConfigurationZone, LightingControl, SaveNodeSetting, NumberOfNeighbourNode |  | 33 |
| SmartLighting/getProximityLighting | Get |  | Get settings of proximity lighting | 33 |
| SmartLighting/getProximityLighting | Get_Ack | LightingControl, NumberOfNeighbourNode |  | 33 |

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LightingControl | Proximity lighting control | String | 20 | Enable / Disable | Enable |  | 33 |
| SaveNodeSetting | Indicating whether to save the setting of number of neighbour nodes | String | 20 | Yes / No | Yes |  | 33 |
| NumberOfNeighbourNode | Listen to number of immediate neighbour nodes for motion status | Number | 10 | 1 to 3 | 3 |  | 33 |

<a id="section-4-1-2-3-6"></a>

###### 4.1.2.3.6 Predictive Lighting

Predictive lighting is used to turn on lights in open areas and multiple paths such that when motion is detected by a sensor (trigger node), the lights in the corresponding trigger zones will be turned on. For example, assuming there are 9 sensors deployed at the T-junction. Sensor 2, 3, 5, 6, 7 and 8 are configured as lighting zone 1 and these sensors are also configured

<a id="pdf-page-34"></a>

<!-- Source PDF page 34 -->

**Figure transcription (PDF p. 34):** A T-junction contains sensors 1–9. Lighting Zone 1 contains sensors 2, 3, 5, 6, 7 and 8; the same sensors are trigger nodes for Zone 1. Motion detected by one of those nodes activates the lights in Zone 1. Sensors 1, 4 and 9 are outside the drawn Zone 1 boundary.

as the trigger nodes that have zone 1 as the trigger zone. In this case, any motion detected by these sensors will turn on the lights in zone 1.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setPredictiveLighting | Set | Transmission, ConfigurationZone, LightingControl | Configure predictive lighting (unicast command to gateway) | 34 |
| SmartLighting/setPredictiveLighting | Set_Ack | Transmission, ConfigurationZone, LightingControl |  | 34 |
| SmartLighting/getPredictiveLighting | Get |  | Get settings of predictive lighting (unicast command to gateway) | 34 |
| SmartLighting/getPredictiveLighting | Get_Ack | LightingControl |  | 34 |

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LightingControl | Predictive lighting control | String | 20 | Enable / Disable | Enable |  | 34 |

<a id="pdf-page-35"></a>

<!-- Source PDF page 35 -->

<a id="section-4-1-2-3-7"></a>

###### 4.1.2.3.7 Timer Profiles

Timer profiles are used to control lighting operation mode based on the time of day, a total 10 profiles are supported. For example, it can be used to turn off lights from 7am to 7pm.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setTimerProfile | Set | Transmission, ConfigurationZone, ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartTime, EndTime, DayOfWeek, Action [Profile 2] ZoneId, StartTime, EndTime, DayOfWeek, Action … [Profile n] ZoneId, StartTime, EndTime, DayOfWeek, Action | Configure up to 10 timer profiles (unicast command to gateway) | 35 |
| SmartLighting/setTimerProfile | Set_Ack | Transmission, ConfigurationZone, ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartTime, EndTime, DayOfWeek, Action [Profile 2] ZoneId, StartTime, EndTime, DayOfWeek, Action … [Profile n] ZoneId, StartTime, EndTime, DayOfWeek, Action |  | 35 |
| SmartLighting/getTimerProfile | Get |  | Get settings of timer profiles (unicast command to gateway) | 35 |
| SmartLighting/getTimerProfile | Get_Ack | ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartTime, EndTime, DayOfWeek, Action [Profile 2] ZoneId, StartTime, EndTime, DayOfWeek, Action … [Profile n] ZoneId, StartTime, EndTime, DayOfWeek, Action |  | 35,36 |

<a id="pdf-page-36"></a>

<!-- Source PDF page 36 -->

Note: [Profile #] in the above table is not the actual field, it is only meant for illustration purpose.

Sample parameters for SET command (SmartLighting/setTimerProfile)

<!-- Example source PDF pages: 36, 37; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "ProfileControl": "Enable",
    "RepeatAction": 30,
    "NumberOfProfile": 2,
    "TimerProfiles": [
      {
        "ZoneId": 1,
        "StartTime": "07:00",
        "EndTime": "19:00",
        "DayOfWeek": "Everyday",
        "Action": "Force_Off"
      },
      {
        "ZoneId": 1,
        "StartTime": "19:00",
        "EndTime": "07:00",
        "DayOfWeek": "Everyday",
        "Action": "Auto"
      }
    ]
  }
}
```

<a id="pdf-page-37"></a>

<!-- Source PDF page 37, continued example above -->

Sample parameters for GET command response (SmartLighting/getTimerProfile)

<!-- Example source PDF pages: 37, 38; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Get_Ack",
    "ProfileControl": "Enable",
    "RepeatAction": 30,
    "NumberOfProfile": 2,
    "TimerProfiles": [
      {
        "ZoneId": 1,
        "StartTime": "07:00",
        "EndTime": "19:00",
        "DayOfWeek": "Everyday",
        "Action": "Force_Off"
      },
      {
        "ZoneId": 1,
        "StartTime": "19:00",
        "EndTime": "07:00",
        "DayOfWeek": "Everyday",
        "Action": "Auto"
      }
    ]
  }
}
```

<a id="pdf-page-38"></a>

<!-- Source PDF page 38, continued example above -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProfileControl | Profile control | String | 20 | Enable / Disable | Enable |  | 38 |
| RepeatAction | Repeat action command per interval | Number | 10 | 0 to 250 min | 30 | Set to 0 to send action command once. | 38 |
| NumberOfProfile | Number of profiles to be set | Number | 10 | 1 to 10 | 5 |  | 38 |
| ZoneId | Lighting zone to apply setting when event is occurred | Number | 10 | 1 to 63 / 255 | 255 | Set to 255 to select all lights under a gateway | 38 |
| StartTime | Start time of event | String | 20 | HH:mm HH - Hour mm - Minute | 07:00 |  | 38 |
| EndTime | End time of event | String | 20 | HH:mm HH - Hour mm - Minute | 19:00 |  | 38 |
| DayOfWeek | Select day of week to monitor event | String | 20 | Weekday /Weekend /Everyday /Holiday | Everyday |  | 38 |
| Action | Perform lighting control when event is occurred | String | 20 | Auto /Force_On /Force_Off ~~Unoccupy_Off~~ | Auto |  | 38 |

<a id="section-4-1-2-3-8"></a>

###### 4.1.2.3.8 Dimming Profiles

Dimming profiles are used to control dim and bright intensity based on time of day, total 10 profiles are supported. For example, it can be used to set the dim intensity of lights to a lower level after midnight to further save energy.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setDimmingProfile | Set | Transmission, ConfigurationZone, ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel [Profile 2] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel … [Profile n] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel | Configure up to 10 dimming profiles (unicast command to gateway) | 38,39 |
| SmartLighting/setDimmingProfile | Set_Ack | Transmission, ConfigurationZone, ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel [Profile 2] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel … [Profile n] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel |  | 39 |
| SmartLighting/getDimmingProfile | Get |  | Get settings of dimming profiles (unicast command to gateway) | 39 |
| SmartLighting/getDimmingProfile | Get_Ack | ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel [Profile 2] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel … [Profile n] ZoneId, StartTime, EndTime, DayOfWeek, DimLevel, BrightLevel |  | 39,40 |

<a id="pdf-page-39"></a>

<!-- Source PDF page 39 -->

<a id="pdf-page-40"></a>

<!-- Source PDF page 40 -->

Note: [Profile #] in the above table is not the actual field, it is only meant for illustration purpose.

Sample parameters for SET command (SmartLighting/setDimmingProfile)

<!-- Example source PDF pages: 40, 41; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "ProfileControl": "Enable",
    "RepeatAction": 30,
    "NumberOfProfile": 2,
    "DimmingProfiles": [
      {
        "ZoneId": 1,
        "StartTime": "07:00",
        "EndTime": "23:59",
        "DayOfWeek": "Everyday",
        "DimLevel": 20,
        "BrightLevel": 254
      },
      {
        "ZoneId": 1,
        "StartTime": "00:00",
        "EndTime": "07:00",
        "DayOfWeek": "Everyday",
        "DimLevel": 10,
        "BrightLevel": 254
      }
    ]
  }
}
```

<a id="pdf-page-41"></a>

<!-- Source PDF page 41, continued example above -->

Sample parameters for GET command response (SmartLighting/getDimmingProfile)

<!-- Example source PDF pages: 41; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Get_Ack",
    "ProfileControl": "Enable",
    "RepeatAction": 30,
    "NumberOfProfile": 2,
    "DimmingProfiles": [
      {
        "ZoneId": 1,
        "StartTime": "07:00",
        "EndTime": "23:59",
        "DayOfWeek": "Everyday",
        "DimLevel": 20,
        "BrightLevel": 254
      },
      {
        "ZoneId": 1,
        "StartTime": "00:00",
        "EndTime": "07:00",
        "DayOfWeek": "Everyday",
        "DimLevel": 10,
        "BrightLevel": 254
      }
    ]
  }
}
```

<a id="pdf-page-42"></a>

<!-- Source PDF page 42 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProfileControl | Profile control | String | 20 | Enable / Disable | Enable |  | 42 |
| RepeatAction | Repeat action command per interval | Number | 10 | 0 to 250 min | 30 | Set to 0 to send action command once. | 42 |
| NumberOfProfile | Number of profiles to be set | Number | 10 | 1 to 10 | 5 |  | 42 |
| ZoneId | Lighting zone to apply setting when event is occurred | Number | 10 | 1 to 63 / 255 | 255 | Set to 255 to select all lights under a gateway | 42 |
| StartTime | Start time of event | String | 20 | HH:mm HH - Hour mm - Minute | 07:00 |  | 42 |
| EndTime | End time of event | String | 20 | HH:mm HH - Hour mm - Minute | 19:00 |  | 42 |
| DayOfWeek | Select day of week to monitor event | String | 20 | Weekday /Weekend /Everyday /Holiday | Everyday |  | 42 |
| DimLevel | Set dim intensity when event is occurred | Number | 10 | 0 to 50 / 254 /255 | 20 | Value is in percentage Set to 254 to keep current dim level unchanged Set to 255 to use default dim level | 42 |
| BrightLevel | Set bright intensity when event is occurred | Number | 10 | 50 to 100 / 254 /255 | 80 | Value is in percentage Set to 254 to keep current bright level unchanged Set to 255 to use default bright level | 42 |

<a id="section-4-1-2-3-9"></a>

###### 4.1.2.3.9 Luminance Profiles

Luminance profiles are used to set the luminance level of lights based on predefined schedule, total 10 profiles are supported. For example, it can be used to set the luminance level of new lights to a lower level initially and subsequently increase the luminance level over the years to compensate LED decay.

<a id="pdf-page-43"></a>

<!-- Source PDF page 43 -->

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setLuminanceProfile | Set | Transmission, ConfigurationZone, ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartDate, EndDate, LuminanceLevel [Profile 2] ZoneId, StartDate, EndDate, LuminanceLevel … [Profile n] ZoneId, StartDate, EndDate, LuminanceLevel | Configure up to 10 luminance profiles (unicast command to gateway) | 43 |
| SmartLighting/setLuminanceProfile | Set_Ack | Transmission, ConfigurationZone, ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartDate, EndDate, LuminanceLevel [Profile 2] ZoneId, StartDate, EndDate, LuminanceLevel … [Profile n] ZoneId, StartDate, EndDate, LuminanceLevel |  | 43 |
| SmartLighting/getLuminanceProfile | Get |  | Get settings of luminance profiles (unicast command to gateway) | 43 |
| SmartLighting/getLuminanceProfile | Get_Ack | ProfileControl, RepeatAction, NumberOfProfile, [Profile 1] ZoneId, StartDate, EndDate, LuminanceLevel [Profile 2] ZoneId, StartDate, EndDate, LuminanceLevel … [Profile n] ZoneId, StartDate, EndDate, LuminanceLevel |  | 43,44 |

<a id="pdf-page-44"></a>

<!-- Source PDF page 44 -->

Note: [Profile #] in the above table is not the actual field, it is only meant for illustration purpose.

Sample parameters for SET command (SmartLighting/setLuminanceProfile)

<!-- Example source PDF pages: 44; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "ProfileControl": "Enable",
    "RepeatAction": 1,
    "NumberOfProfile": 2,
    "LuminanceProfiles": [
      {
        "ZoneId": 1,
        "StartDate": "01-01-2020",
        "EndDate": "31-12-2020",
        "LuminanceLevel": 80
      },
      {
        "ZoneId": 1,
        "StartDate": "01-01-2021",
        "EndDate": "31-12-2021",
        "LuminanceLevel": 85
      }
    ]
  }
}
```

<a id="pdf-page-45"></a>

<!-- Source PDF page 45 -->

Sample parameters for GET command response (SmartLighting/getLuminanceProfile)

<!-- Example source PDF pages: 45; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Get_Ack",
    "ProfileControl": "Enable",
    "RepeatAction": 1,
    "NumberOfProfile": 2,
    "LuminanceProfiles": [
      {
        "ZoneId": 1,
        "StartDate": "01-01-2020",
        "EndDate": "31-12-2020",
        "LuminanceLevel": 80
      },
      {
        "ZoneId": 1,
        "StartDate": "01-01-2021",
        "EndDate": "31-12-2021",
        "LuminanceLevel": 85
      }
    ]
  }
}
```

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProfileControl | Profile control | String | 20 | Enable / Disable | Enable |  | 45 |
| RepeatAction | Repeat action command per interval | Number | 10 | 0 to 24 hours | 1 | Set to 0 to send action command once. | 45 |
| NumberOfProfile | Number of profiles to be set | Number | 10 | 1 to 10 | 5 |  | 45 |
| ZoneId | Lighting zone to apply setting when event is occurred | Number | 10 | 1 to 63 / 255 | 255 | Set to 255 to select all lights under a gateway | 45 |
| StartDate | Start date of event | String | 20 | dd-MM-yyyy dd - Day MM - Month yyyy - Year | 01-01-2020 |  | 46 |
| EndDate | End date of event | String | 20 | dd-MM-yyyy dd - Day MM - Month yyyy - Year | 31-12-2020 |  | 46 |
| LuminanceLevel | Set luminance level when event is occurred | Number | 10 | 50 to 100 | 80 | Value is in percentage | 46 |

<a id="pdf-page-46"></a>

<!-- Source PDF page 46 -->

<a id="section-4-1-2-3-10"></a>

###### 4.1.2.3.10 Daylight Profile

Daylight profile is used to control lighting operation mode based on ambient daylight, only one profile is supported to control lights under a gateway. For example, it can be used to activate sensor-based lighting control during overcast day as long as any of the designated photocell sensors indicate dim daylight.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setDaylightProfile | Set | Transmission, ConfigurationZone, ProfileControl, RepeatAction, ZoneId, StartTime, EndTime, PhotoSensor1, PhotoSensor2, PhotoSensor3, DimThreshold, BrightThreshold, DimAction, BrightAction | Configure daylight profile (unicast command to gateway) | 46 |
| SmartLighting/setDaylightProfile | Set_Ack | Transmission, ConfigurationZone, ProfileControl, RepeatAction, ZoneId, StartTime, EndTime, PhotoSensor1, PhotoSensor2, PhotoSensor3, DimThreshold, BrightThreshold, DimAction, BrightAction |  | 46 |
| SmartLighting/getDaylightProfile | Get |  | Get daylight profile settings (unicast command to gateway) | 46 |
| SmartLighting/getDaylightProfile | Get_Ack | ProfileControl, RepeatAction, ZoneId, StartTime, EndTime, PhotoSensor1, PhotoSensor2, PhotoSensor3, DimThreshold, BrightThreshold, DimAction, BrightAction |  | 46,47 |

<a id="pdf-page-47"></a>

<!-- Source PDF page 47 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProfileControl | Profile control | String | 20 | Enable / Disable | Enable |  | 47 |
| RepeatAction | Repeat action command per interval | Number | 10 | 0 to 250 min | 30 | Set to 0 to send action command once. | 47 |
| ZoneId | Lighting zone to apply setting when event is occurred | Number | 10 | 1 to 63 / 255 | 255 | Set to 255 to select all lights under a gateway | 47 |
| StartTime | Start time of event | String | 20 | HH:mm HH - Hour mm - Minute | 07:00 |  | 47 |
| EndTime | End time of event | String | 20 | HH:mm HH - Hour mm - Minute | 19:00 |  | 47 |
| PhotoSensor | Photo sensor id | String | 255 |  | SmartLighting-ST-600230-01010215 | PhotoSensor2 and PhotoSensor3 are optional, set to “Nil” if not required | 47 |
| DimThreshold | Threshold to detect dim daylight | Number | 10 | 50 to 1000 | 200 | Value is in lux | 47 |
| BrightThreshold | Threshold to detect bright daylight | Number | 10 | 50 to 1000 | 400 | Value is in lux | 47 |
| DimAction | Perform lighting control under dim daylight | String | 20 | Auto /Force_On /Force_Off | Auto |  | 47 |
| BrightAction | Perform lighting control under bright daylight | String | 20 | Auto /Force_On /Force_Off | Force_Off |  | 47 |

<a id="section-4-1-2-3-11"></a>

###### 4.1.2.3.11 Rain Profile

Rain profile is used to control lighting operation mode based on rainfall, only one profile is supported to control lights under a gateway. For example, it can be used to keep lights fully on in surface car park as long as any of the designated rain sensors indicate heavy downpour.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setRainProfile | Set | Transmission, ConfigurationZone, ProfileControl, RepeatAction, ZoneId, StartTime, EndTime, RainSensor1, RainSensor2, RainSensor3, LightRainThreshold, HeavyRainThreshold, LightRainAction, HeavyRainAction | Configure rain profile (unicast command to gateway) | 47,48 |
| SmartLighting/setRainProfile | Set_Ack | Transmission, ConfigurationZone, ProfileControl, RepeatAction, ZoneId, StartTime, EndTime, RainSensor1, RainSensor2, RainSensor3, LightRainThreshold, HeavyRainThreshold, LightRainAction, HeavyRainAction |  | 48 |
| SmartLighting/getRainProfile | Get |  | Get rain profile settings (unicast command to gateway) | 48 |
| SmartLighting/getRainProfile | Get_Ack | ProfileControl, RepeatAction, ZoneId, StartTime, EndTime, RainSensor1, RainSensor2, RainSensor3, LightRainThreshold, HeavyRainThreshold, LightRainAction, HeavyRainAction |  | 48 |

<a id="pdf-page-48"></a>

<!-- Source PDF page 48 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProfileControl | Profile control | String | 20 | Enable / Disable | Enable |  | 48 |
| RepeatAction | Repeat action command per interval | Number | 10 | 0 to 250 min | 30 | Set to 0 to send action command once. | 48 |
| ZoneId | Lighting zone to apply setting when event is occurred | Number | 10 | 1 to 63 / 255 | 255 | Set to 255 to select all lights under a gateway | 48 |
| StartTime | Start time of event | String | 10 | HH:mm HH - Hour mm - Minute | 19:00 |  | 48 |
| EndTime | End time of event | String | 10 | HH:mm HH - Hour mm - Minute | 23:59 |  | 48 |
| RainSensor | Rain sensor id | String | 255 |  | SmartLighting-ST-600230-01010215 | RainSensor2 and RainSensor3 are optional, set to “Nil” if not required | 48 |
| LightRainThreshold | Threshold to detect light rain | Number | 10 | 5 to 255 | 5 | Value is in terms of number of pulses per minute (each pulse is corresponding to 0.01mm of rainfall) | 48,49 |
| HeavyRainThreshold | Threshold to detect heavy rain | Number | 10 | 5 to 255 | 30 | Value is in terms of number of pulses per minute (each pulse is corresponding to 0.01mm of rainfall) | 49 |
| LightRainAction | Perform lighting control under light rain | String | 20 | Auto /Force_On /Force_Off | Auto |  | 49 |
| HeavyRainAction | Perform lighting control under heavy rain | String | 20 | Auto /Force_On /Force_Off | Force_On |  | 49 |

<a id="pdf-page-49"></a>

<!-- Source PDF page 49 -->

<a id="section-4-1-2-3-12"></a>

###### 4.1.2.3.12 Daylight Harvesting Profile

Daylight harvesting profile is used to adjust luminance level of each group of lights according to the ambient daylight measured using photocell sensor(s), only one profile is supported to control multiple daylight harvesting zones under a gateway. For example, it can be used to adjust luminance level of the lights near the entrance / exit of a basement car park.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/setDaylightHarvestingProfile | Set | Transmission, ConfigurationZone, ProfileControl, RepeatActivation, OverallZone, StartTime, EndTime, DayOfWeek, DaylightThreshold, MinLuminanceLevel, MaxLuminanceLevel | Configure daylight harvesting profile (unicast command to gateway) | 49 |
| SmartLighting/setDaylightHarvestingProfile | Set_Ack | Transmission, ConfigurationZone, ProfileControl, RepeatActivation, OverallZone, StartTime, EndTime, DayOfWeek, DaylightThreshold, MinLuminanceLevel, MaxLuminanceLevel |  | 49 |
| SmartLighting/getDaylightHarvestingProfile | Get |  | Get daylight harvesting profile settings (unicast command to gateway) | 49 |
| SmartLighting/getDaylightHarvestingProfile | Get_Ack | ProfileControl, RepeatActivation, OverallZone, StartTime, EndTime, DayOfWeek, DaylightThreshold, MinLuminanceLevel, MaxLuminanceLevel |  | 49,50 |

<a id="pdf-page-50"></a>

<!-- Source PDF page 50 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProfileControl | Profile control | String | 20 | Enable / Disable | Enable |  | 50 |
| RepeatActivation, | Repeat activation command per interval | Number | 10 | 0 to 250 min | 30 | Set to 0 to send activation command once. | 50 |
| OverallZone | Overall daylight harvesting zone which consists of the sensor nodes in all the daylight harvesting zones | Number | 10 | 1 to 63 | 60 |  | 50 |
| StartTime | Start time of event | String | 20 | HH:mm HH - Hour mm - Minute | 07:00 |  | 50 |
| EndTime | End time of event | String | 20 | HH:mm HH - Hour mm - Minute | 19:00 |  | 50 |
| DayOfWeek | Select day of week for event to take effect | String | 20 | Weekday /Weekend /Everyday /Holiday | Everyday |  | 50 |
| DaylightThreshold | Daylight threshold which is used to generate multiple daylight levels | Number | 10 | 400 to 1000 | 1000 | Value is in lux | 50 |
| MaxLuminanceLevel | Maximum luminance level corresponds to dim daylight | Number | 10 | 50 to 100 | 90 | Value is in percentage | 50 |
| MinLuminanceLevel | Minimum luminance level corresponds to bright daylight | Number | 10 | 0 to 50 | 10 | Value is in percentage | 50 |

<a id="pdf-page-51"></a>

<!-- Source PDF page 51 -->

**Figure transcription (PDF p. 51):** Daylight threshold = 1000 lux; the four boundaries shown are 1000, 750, 500 and 250 lux.

| Band (from brightest ambient to dimmest ambient) | Ambient range indicated by the diagram | Min 0%, Max 100% | Min 10%, Max 90% |
| --- | --- | --- | --- |
| 1 | Above the 1000 lux boundary | 0% | 10% |
| 2 | Between 1000 and 750 lux | 25% | 30% |
| 3 | Between 750 and 500 lux | 50% | 50% |
| 4 | Between 500 and 250 lux | 75% | 70% |
| 5 | Below the 250 lux boundary | 100% | 90% |

Conversion note: the diagram does not specify which band includes a value exactly on a boundary.

Note: The daylight threshold and min/max luminance level are used to generate 5 light bands for luminance adjustment based on measured ambient daylight. The daylight threshold is divided by 4 to generate 4 daylight levels whereas the difference of minimum and maximum luminance is divided by 4 to generate 4 luminance levels. For example:

<a id="section-4-1-2-3-13"></a>

###### 4.1.2.3.13 Normal Light Automatics Test

The following commands are used to test normal light to detect light dim and flicker.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/activateLightTest | Set | Transmission, ConfigurationZone | Activate lighting test. Alarm message will send out if light test failed. | 51 |
| SmartLighting/activateLightTest | Set_Ack | Transmission, ConfigurationZone |  | 51 |
| SmartLighting/setLightTestSchedule | Set | Transmission, ConfigurationZone, TestControl, StartTime | Setup a test schedule to test all lights under a gateway. Alarm message will send out if light test failed. (unicast command to gateway) | 51 |
| SmartLighting/setLightTestSchedule | Set_Ack | Transmission, ConfigurationZone, TestControl, StartTime |  | 51 |
| SmartLighting/getLightTestSchedule | Get |  | Get schedule of lighting test. (unicast command to gateway) | 51 |
| SmartLighting/getLightTestSchedule | Get_Ack | TestControl, StartTime |  | 51 |
| SmartLighting/getLightStatus | Get |  | Get light health status | 51 |
| SmartLighting/getLightStatus | Get_Ack | LightStatus |  | 51 |

<a id="pdf-page-52"></a>

<!-- Source PDF page 52 -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TestControl | Auto test control | String | 20 | Enable / Disable | Enable |  | 52 |
| StartTime | Start time to perform lighting test | String | 20 | HH:mm HH - Hour M m - Minute | 03:00 |  | 52 |
| LightStatus | Health status of light | String | 20 | Normal /Dim /Flicker /Dim_Flicker /Off | Normal |  | 52 |

<a id="section-4-1-2-3-14"></a>

###### 4.1.2.3.14 Emergency Light Automatics Test

The following commands are used to perform manual and auto test for emergency lights.

| Event Type | Command Type | Fields | Remarks | Source PDF page |
| --- | --- | --- | --- | --- |
| SmartLighting/startELightTest | Set | Transmission, ConfigurationZone, TestType | Start emergency lighting test | 52 |
| SmartLighting/startELightTest | Set_Ack | Transmission, ConfigurationZone, TestType |  | 52 |
| SmartLighting/stopELightTest | Set | Transmission, ConfigurationZone | Stop emergency lighting test | 52 |
| SmartLighting/stopELightTest | Set_Ack | Transmission, ConfigurationZone |  | 52 |
| SmartLighting/setELightAutoTest | Set | Transmission, ConfigurationZone, TestControl | Control auto test (unicast command to gateway) | 52 |
| SmartLighting/setELightAutoTest | Set_Ack | Transmission, ConfigurationZone, TestControl |  | 52 |
| SmartLighting/getELightAutoTest | Get |  | Get auto test control status (unicast command to gateway) | 52 |
| SmartLighting/getELightAutoTest | Get_Ack | TestControl |  | 52 |
| SmartLighting/setELightTestSchedule | Set | Transmission, ConfigurationZone, NumberOfProfile, [Profile 1] ProfileControl, ZoneId, FunctionalTestDate, FunctionalTestTime, DurationTestDate, DurationTestTime … [Profile n] ProfileControl, ZoneId, FunctionalTestDate, FunctionalTestTime, DurationTestDate, DurationTestTime | Setup test schedules for auto test (unicast command to gateway) | 52,53 |
| SmartLighting/setELightTestSchedule | Set_Ack | Transmission, ConfigurationZone, NumberOfProfile, [Profile 1] ProfileControl, ZoneId, FunctionalTestDate, FunctionalTestTime, DurationTestDate, DurationTestTime … [Profile n] ProfileControl, ZoneId, FunctionalTestDate, FunctionalTestTime, DurationTestDate, DurationTestTime |  | 53 |
| SmartLighting/getELightTestSchedule | Get |  | Get test schedules for auto test (unicast command to gateway) | 53 |
| SmartLighting/getELightTestSchedule | Get_Ack | NumberOfProfile, [Profile 1] ProfileControl, ZoneId, FunctionalTestDate, FunctionalTestTime, DurationTestDate, DurationTestTime … [Profile n] ProfileControl, ZoneId, FunctionalTestDate, FunctionalTestTime, DurationTestDate, DurationTestTime |  | 53 |
| SmartLighting/getELightTestResult | Get |  | Get result of emergency lighting test | 53 |
| SmartLighting/getELightTestResult | Get_Ack | Test Time, TestType, TestResult, FailureType, NotTested, BatteryVoltage |  | 53 |

<a id="pdf-page-53"></a>

<!-- Source PDF page 53 -->

<a id="pdf-page-54"></a>

<!-- Source PDF page 54 -->

Note: [Profile #] in the above table is not the actual field, it is only meant for illustration purpose.

Sample parameters for SET command (SmartLighting/setELightTestSchedule)

<!-- Example source PDF pages: 54; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "NumberOfProfile": 2,
    "AutoTestProfiles": [
      {
        "ProfileControl": "Enable",
        "ZoneId": 1,
        "FunctionalTestDate": "01-01-2020",
        "FunctionalTestTime": "01:00",
        "DurationTestDate": "01-15-2020",
        "DurationTestTime": "03:00"
      },
      {
        "ProfileControl": "Enable",
        "ZoneId": 2,
        "FunctionalTestDate": "02-01-2020",
        "FunctionalTestTime": "01:00",
        "DurationTestDate": "02-15-2020",
        "DurationTestTime": "03:00"
      }
    ]
  }
}
```

Sample parameters for GET command response (SmartLighting/getELightTestSchedule)

<!-- Example source PDF pages: 54, 55; formatting normalized; Parameters fragment wrapped in an object -->

```json
{
  "Parameters": {
    "CommandType": "Get_Ack",
    "NumberOfProfile": 2,
    "AutoTestProfiles": [
      {
        "ProfileControl": "Enable",
        "ZoneId": 1,
        "FunctionalTestDate": "01-01-2020",
        "FunctionalTestTime": "01:00",
        "DurationTestDate": "01-15-2020",
        "DurationTestTime": "03:00"
      },
      {
        "ProfileControl": "Enable",
        "ZoneId": 2,
        "FunctionalTestDate": "02-01-2020",
        "FunctionalTestTime": "01:00",
        "DurationTestDate": "02-15-2020",
        "DurationTestTime": "03:00"
      }
    ]
  }
}
```

<a id="pdf-page-55"></a>

<!-- Source PDF page 55, continued example above -->

**Data Dictionary**

| Field Name | Description | Data Type | Max Length | Possible Values | Sample Values | Remarks | Source PDF page |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NumberOfProfile | Number of profiles to be set | Number | 10 | 1 to 20 | 5 |  | 55 |
| ProfileControl | Test schedule control | String | 20 | Enable / Disable | Enable |  | 55 |
| ZoneId | Lighting zone for auto test | Number | 10 | 1 to 63 | 1 |  | 55 |
| FunctionalTestDate | Date of functional test | String | 20 | dd-MM-yyyy dd - Day MM - Month yyyy - Year | 01-10-2020 |  | 55 |
| FunctionalTestTime | Time of functional test | String | 20 | HH:mm HH - Hour Mm - Minute | 01:00 |  | 55 |
| DurationTestDate | Date of duration test | String | 20 | dd-MM-yyyy dd - Day MM - Month yyyy - Year | 15-10-2020 |  | 56 |
| DurationTestTime | Time of duration test | String | 20 | HH:mm HH - Hour Mm - Minute | 03:00 |  | 56 |
| TestTime | Date and time of lighting test | String | 25 | yyyy-MM-dd HH:mm:ss.SSS yyyy - Year MM - Month dd - Day HH - Hour 24hr format mm - Minute ss - Second SSS - Millisecond | 2020-01-12 10:49:50.272 |  | 56 |
| TestType | Test type | String | 25 | Functional /Duration /Commissioning | Functional |  | 56 |
| TestControl | Auto test control | String | 20 | Enable / Disable | Enable |  | 56 |
| TestResult | Test result | String | 25 | Passed /Failed /Not_Tested /Test_In_Progress /Result_Not_Available | Passed |  | 56 |
| FailureType | Type of failure | String | 25 | Light_Fail /Battery_Fail /Charger_Fail /Light_Dim /Light_Flicker /Light_Dim_Flicker | Battery_Fail | For test failed case | 56 |
| NotTested | Reason for not tested | String | 50 | Not_Responding /Emergency_Mode /Test_Button_Pressed /Light_Power_Not_Calibrated /Battery_Below_Nominal_Voltage /Battery_Not_Fully_Charged /Battery_Removed /Switch_Over_Fail /Incorrect_Nominal_Battery_Voltage /Battery_Low /Charger_fault | Battery_Removed | For not tested case | 56 |
| BatteryVoltage | Battery voltage after lighting test | Number | 10 | 3.6 to 12 | 3.5 | Value is in voltage | 56 |

<a id="pdf-page-56"></a>

<!-- Source PDF page 56 -->

<a id="pdf-page-57"></a>

<!-- Source PDF page 57 -->

<a id="section-5"></a>

## 5 POINTS TO BE NOTED

- SensorId should be unique, as elaborated in Appendix III.

- If the sensor does not follow the ICD specifications, the Smart Hub will not show sensor readings or alarms.

- Prior to send sensor data, sensorIds must be added into master data and loaded in the Smart Hub system.

- Sensors must filter out the duplicate records in the flat files and empty readings.

- Records in a file must be sequential with respect to the time.

<a id="pdf-page-58"></a>

<!-- Source PDF page 58 -->

<a id="section-6"></a>

## 6 MASTER DATA CONFIGURATION

<a id="section-6-1"></a>

### 6.1

The Smart Hub system requires the master device list and basic properties of

the each of the devices to be configured and linked to each device object. This is a one-off action. The data is populated in accordance to the physical device hierarchical relation. The system is designed to take in large numbers of sensors properties without the upfront definition of individual sensor. As per the design, the properties of specific sensor can be represented as key value pair in static and dynamic parameters column of the master data. Hence any properties can be added to static properties. The inputs in this excel will fall under:

- Smart Hub Attributes - mandatory attributes required for Smart Hub integration

- Sensor Attributes - attributes specific to the sensor (e.g. IOT sensor specifications, model no. , brand of sensor)

- Specific Attributes - any other additional miscellaneous details associated with the sensor. The Master Data establishes an identity for sensor/device and tracks metadata such as device's attributes, capabilities, geo info, resource path, and so on. This consistently formatted unique id would be a primary key which can be used as reference in event data or any data set.

<a id="section-6-2"></a>

### 6.2 Sensor Details for Smart Hub

The format below is an example. A detailed spreadsheet will be provided to the sensor vendor to populate.

<a id="pdf-page-59"></a>

<!-- Source PDF page 59 -->

Table 6-1: Master Data File definition

**Smart Hub Attributes:**

| Property | Description | Sample Value | Source PDF page |
| --- | --- | --- | --- |
| SensorId | &lt;SensorType&gt;-&lt;Vendor&gt;-&lt;PostalCode&gt;-&lt;GenericIdentifier&gt; Vendor name must be alphanumeric without special characters; Instead of Postal code, location code can be used if there is no postal code available for the location. E.g. JE-OUTDOOR A generic Identifier is used so that even when the specific sensor is replaced by new hardware, Smart Hub recognises it as the same sensor point. | See Appendix III | 59 |
| Sensor Type | Sensor type | Smart Lighting | 59 |
| Sensor Display Name | Name to be displayed in Smart Hub’s real time monitoring software GUI | Appendix III | 59 |
| Postal Code | Postal code, if the postcode is not available just add some unique code eg: 99990001 | 600321 | 59 |
| X | x/Easting | 34.345234 | 59 |
| Y | y/Northing | 64.345454 | 59 |
| Z | z/height | 22.22 | 59 |
| Location Descriptor | To display the location name in the smart hub system. | See Appendix III | 59 |
| Sensor Manufacturing Company | Brand/Vendor | ST Engineering | 59 |
| Sensor Model | Model | MHW33 | 59 |

**Sensor Attributes:**

Attributes specific to sensors will be required according to the sensor type. They are required for Smart Hub as well as for compliance with WOG sensor attribute conventions.

<a id="pdf-page-60"></a>

<!-- Source PDF page 60 -->

The sample values in the parameters/static properties column are for illustration purpose and they may not be real values of the sensors. The purpose of the static properties list to add static properties like Software Version, and compass bearing, etc. In the master data, the attribute names (headers) should include the units. For e.g. grid_frequency (Hz).

**Specific Attributes:**

These miscellaneous attributes are meant for any additional details specific to the sensor type or site-specific information such as the Mechanical & Electrical system details the sensor is tagged to. Non-exhaustive examples are:

- Water pump motor specifications and installation date for Smart Pumps;

- Smart Lighting device location, gateway device no., connected light devices, light model;

- Water Meter sensor flowrate detection range, meter class, battery life etc.

<a id="section-6-3"></a>

### 6.3 Master Data Considerations

- X, Y and Z coordinates shall be provided in svy21 reference system.

- Any specific parameter with respect to sensor type can be added as key value pair, if you don’t have any value at the moment just put it as N.A (Not applicable)

<a id="pdf-page-61"></a>

<!-- Source PDF page 61 -->

<a id="section-appendix-i"></a>

## Appendix I – Glossary of Terms

| Term | Definition |
| --- | --- |
| GUI | Graphical User Interface |
| HDB | Housing & Development Board |
| ICD | Interface Control Document |
| JSON | JavaScript Object Notation |
| MQTT | Message Queue Telemetry Transport |
| Qos | Quality of Service |
| SMS | Short Messaging Service |
| SSL | Secure Sockets Layer |
| TLS | Transport Layer Security |
| URL | Uniform Resource Locator |
| WOG | Whole of Government |

<a id="pdf-page-62"></a>

<!-- Source PDF page 62 -->

**Embedded-object note (PDF p. 62):** An Excel icon is labelled `Master Data 20210801 Template.xlsx`. This Markdown converts the visible PDF content; the spreadsheet contents are not supplied by that icon.

<a id="section-appendix-ii"></a>

## Appendix II– Masterdata Attributes Sample

This is a sample of the expected Masterdata attributes. The actual Masterdata document and its attributes will be in an excel document in table format. The Contractor shall obtain the latest Masterdata document from HDB Building and Research Institute (BRI) and adhere to the latest format.

**Water Meter Attributes (example)**

| Attribute Group | Attribute Name | Description | Sample Value | Source PDF page |
| --- | --- | --- | --- | --- |
| Smart Hub Attribute | Sensor Id | The sensor ID that serves as the unique identifier for each sensor Syntax: SensorType-Vendor-Postalcode-GenericIdentifier e.g. Water-Minerva-700123-WashBay1-Meter1 | Water-minerva-600209-209-JEST21-Water-Wbay-01 | 62 |
| Smart Hub Attribute | Sensor Type | To provide information on the sensor type or modality. For example, camera, noise, temperature, humidity, wind…etc. | Water Sub-Meter | 62 |
| Smart Hub Attribute | Sensor Display Name | To display the name in the smart hub system Syntax: DisplayName e.g. WaterMeter-WashBay1 (no spaces, use hyphen) | 209JEST21 | 62 |
| Smart Hub Attribute | Postal Code | If postal code is not available, location code should be given and this location code should be map to Town Council and to address | 600209 | 62 |
| Smart Hub Attribute | X Coordinate | To provide x-coordinate position of the sensor based on SVY21 reference system (minimum 3 decimal places). | 17625.0213 | 62 |
| Smart Hub Attribute | Y Coordinate | To provide y-coordinate position of the sensor based on SVY21 reference system (minimum 3 decimal places). | 35555.6563 | 62 |
| Smart Hub Attribute | Z Coordinate | To provide z-coordinate / height position (in metres) of the sensor based on SVY21 reference system (minimum 3 decimal places). | 0 | 62 |
| Smart Hub Attribute | Location Descriptor | To display the location name in the smart hub system Syntax : Postalcode_LocationName e.g. 700123_WashBay1 (no spaces, use underscore) | 600209-Water-WBay-01 | 62 |
| Smart Hub Attribute | Sensor Manufacturer Company | To provide manufacturer of the sensor | Sensus Advantech | 62 |
| Smart Hub Attribute | Sensor Model | To provide the model of the sensor | HRI &amp; ADAM-6015 | 62 |
| Sensor Specific Attribute | Sensor Serial Number | To provide the sensor's manufacturing serial number | Refer to SensorID | 63 |
| Sensor Specific Attribute | Latitude | To provide latitude if unable to obtain X-coordinate based on SVY21 reference system. |  | 63 |
| Sensor Specific Attribute | Longtitude | To provide latitude if unable to obtain Y-coordinate based on SVY21 reference system. |  | 63 |
| Sensor Specific Attribute | Sensor Maintenance Company | To provide name of the contractor who is responsible for the maintenance |  | 63 |
| Sensor Specific Attribute | Type of Deployment | Fixed or Mobile* [Note: Mobile deployment means the sensor is portable and has no fixed location (e.g. Bodycam)] | Fixed | 63 |
| Sensor Specific Attribute | Existing_Planned_EnvisionedSensors | To indicate if the sensors are (a) Existing, (b) Planned (to be deployed in the next 5 years), or (c) Envisioned (in POC or research stage) | Existing | 63 |
| Sensor Specific Attribute | Unit* | To provide the unit of measurement of the data collected by the sensor. For example, dB, °C, °F…etc. This field is required to be duplicated for each type of reading | Litres | 63 |
| Sensor Specific Attribute | Range* | To provide the operational range at which the sensor is sensing or collecting the data e.g. 10-100 deg. This field is required to be duplicated for each type of reading unless it has been indicated otherwise | The sensors (i.e. HRI pulsars are attached directly on top of the surface of the water meters to collect the data) | 63 |
| Sensor Specific Attribute | Sensor Coverage | To provide a brief estimation on the area the sensor is sensing or collecting data. For example 15m radius. | NA | 63 |
| Sensor Specific Attribute | Power Consumption | To provide information on power consumed by the sensor (e.g. LR44 battery, 40W) | 2W | 63 |
| Sensor Specific Attribute | Power Source | To provide information on the power source. For example, solar, AC mains, DC mains, UPS/ Battery, POE…etc. | 24DVC | 63 |
| Sensor Specific Attribute | Network Connectivity | To provide information on network connectivity type. (e.g. 4G 3GB Plan, CAT5, Fibre, WiFi, Wireless Sensor Network) | CAT5 from sensor (i.e. ADAM) to ethernet port at switchroom | 63 |
| Sensor Specific Attribute | Network Connectivity Provider | To provide information on the service provider for connectivity (e.g. StarHub, SingTel, M1, SPTel) | CAT5 from sensor (i.e. ADAM Controller) to ethernet port at switchroom | 63 |
| Sensor Specific Attribute | Connectivity Contract Expiry | When the existing contract for network connectivity expires | Dependent on the service contract expiry of the electrical sub-meters | 63 |
| Sensor Specific Attribute | Data Collection Mode | To indicate mode of sensor data collection: (a) Continuously in Real-Time, or (b) Every X minutes/hours, or (c) By Trigger | Every 1 min | 63 |
| Sensor Specific Attribute | Data Transmission Mode | To indicate if the sensor is transmitting data: (a) Continuously in Real-Time, or (b) Every X minutes/hours, or (c) By Trigger | Every 15 mins | 63 |
| Sensor Specific Attribute | Data Transmission | To indicate (a) Real-Time [RT] or (b) Historical [H], for data transmission requirement. | Historical (1 file containing 15 lines of data captured every minute will be sent every 15 mins). | 64 |
| Sensor Specific Attribute | Bandwidth | Bandwidth required by sensor for data transmission (e.g. 10 Mbps, 10Kbps) |  | 64 |
| Sensor Specific Attribute | Data Usage Per Month (Mbytes) | Total data usage (sent and received) by each sensor per month (e.g. 0.1 MB, 100 MB) | 3.1 MB (based on estimate of 100Kb per day) | 64 |
| Sensor Specific Attribute | Availability (%) | Service Level Agreement (SLA) -Network Availability (e.g. ≥ 99%) |  | 64 |
| Sensor Specific Attribute | Compass Bearing | To provide indicative direction (in degrees based on True North) where the sensor is looking | Not applicable | 64 |
| Sensor Specific Attribute | Resiliency | (E.g. (a) Path diversity, (b) Exchange Diversity, (c) Path &amp; Exchange Diversity, (d). Nil) |  | 64 |
| Sensor Specific Attribute | Security | Security measures implemented for network traffic, if any (E.g. VPN, VPN + Encryption, Nil) |  | 64 |
| Sensor Specific Attribute | Installation Date of Sensor Deployment | To provide installation date (dd/mm/yy) of sensor deployment. | to be installed | 64 |
| Sensor Specific Attribute | Maintenance Frequency | To provide the maintenance frequency of the sensor device (i.e. 1 Year, 2 Years etc…) | Every 5 years | 64 |
| Sensor Specific Attribute | Quantity Per Location | Not applicable for Mobile sensors. To fill in if there are 2 or more sensors in the same location | 1 per location | 64 |
| Miscellaneous Attribute | Maximum Flow Rate | To indicate the max range in which the water sub-meter is able to read | 3 L/hr | 64 |
| Miscellaneous Attribute | Minimum Flow Rate | To indicate the min range in which the water sub-meter is able to read | 3125 L/hr | 64 |
| Miscellaneous Attribute | Water Tariff | The Tariff imposed on water consumption |  | 64 |
| Miscellaneous Attribute | Class Type | To indicate the class type of the water-submeter | Class C | 64 |
| Miscellaneous Attribute | Meter Type | To indicate the meter type of the water-submeter | Volumetric | 64 |
| Miscellaneous Attribute | Service Type | To indicate whether the tap that the water submeter is monitoring is serving residential or common services | Common services | 64 |
| Miscellaneous Attribute | Pulsar Type | Type of pulsar | Inductive | 64 |
| Miscellaneous Attribute | Resolution | To indicate the Pulse Weight specification | 1Litre/pulse | 64 |
| Miscellaneous Attribute | Battery Life | To indicate the battery life of the Pulsar | approx. 5-10 years | 64 |

<a id="pdf-page-63"></a>

<!-- Source PDF page 63 -->

<a id="pdf-page-64"></a>

<!-- Source PDF page 64 -->

<a id="pdf-page-65"></a>

<!-- Source PDF page 65 -->

<a id="section-appendix-iii"></a>

## Appendix III – Nomenclature for Sensor Naming and Masterdata

| Smart System | SenderId (use hyphens) | SensorId (use hyphens) | Sensor Display Name (no space; hyphen for hierarchy) | Location Descriptor (no space; underscore between postal code and location) | Source PDF page |
| --- | --- | --- | --- | --- | --- |
| Smart Water Pump | SensorType-Postalcode-AggregatorIdentifier e.g. Pump-700123-BoosterPumpRoom | SensorType-Vendor-Postalcode-GenericIdentifier e.g. Pump-Ademco-700123-BoosterPumpRoom-ControlPanel Pump-Ademco-700123-BoosterPumpRoom-Pump1 | DisplayName e.g. ControlPanel Pump1 | Postalcode_LocationName e.g. 700123_BoosterPumpRoom | 65 |
| Smart Water Sub-Meter | SensorType-Postalcode-AggregatorIdentifier e.g. Water-700123-WashBay1 | SensorType-Vendor-Postalcode-GenericIdentifier e.g. Water-Minerva-700123-WashBay1-Meter1 | DisplayName e.g. WaterMeter1 | Postalcode_LocationName e.g. 700123_WashBay1 | 65 |
| Power Consumption Fault Detection Monitoring System (PCFDMS) | SensorType-Postalcode-AggregatorIdentifier e.g. PCFDMS-700123-1 [1 or 2 for the different Consumer Switch Room] | SensorType-Vendor-Postalcode-GenericIdentifier e.g. PCDFMS-Gathergates-700123-1-Q1-M1 PCDFMS-Gathergates-700123-1-Q1-ESB1 (At individual sensor level) | DisplayName e.g. PCFDMS-Q1-M1 | Postalcode_LocationName e.g. 700123_SwitchRoom1 | 65 |
| Smart Lighting System | SensorType-Postalcode-AggregatorIdentifier e.g. SmartLighting-700123-01 | SensorType-Vendor-Postalcode-GenericIdentifier e.g. SmartLighting-ST-700123-01010201 SmartLighting-ST-700123-01010202 SmartLighting-ST-700123-01010203 | DisplayName e.g. MotionSensor-1 MotionSensor-2 | Postalcode_LocationName e.g. 700123_LiftLobby 700123_Level1 | 66 |
| Urbanwater Harvesting System | SensorType-Postalcode-AggregatorIdentifier e.g UWHS-700123-RainwaterTreatmentRoom | SensorType-Vendor-Postalcode-GenericIdentifier e.g. UWHS-ACE-700123-PUBTopup UWHS-ACE-700123-Washing UWHS-ACE-700123-Irrigation | DisplayName e.g. WaterMeter-PUBTopup WaterMeter-Washing WaterMeter-Irrigation | Postalcode_LocationName e.g. 700123_RainwaterTreatmentRoom | 66 |
| Smart Irrigation | SensorType-Postalcode-AggregatorIdentifier e.g. SmartIrrigation-700123-B1 | SensorType-Vendor-Postalcode-GenericIdentifier e.g. SmartIrrigation-ATS-700123-B1-1 SmartIrrigation-ATS-700123-B1-2 SmartIrrigation-ATS-700123-L2-1 | DisplayName e.g. Moisturesensor-1 Moisturesensor-2 | Postalcode_LocationName e.g. 700123_B1 700123_L2 | 66 |
| Smart Rainwater Sump Pump | SensorType-Postalcode-AggregatorIdentifier e.g. RWSPump-700123-B1 | SensorType-Vendor-Postalcode-GenericIdentifier e.g. RWSPump-Company-700123-B1-1 | DisplayName e.g. RainwaterSumpPump-1 | Postalcode_LocationName e.g. 700123_Basement1 | 67 |
| Carpark Mechanical Ventilation Monitoring | SensorType-Postalcode-AggregatorIdentifier e.g. CarparkMV-700123-B1 | SensorType-Vendor-Postalcode-GenericIdentifier e.g. CarparkMV-Colt-700123-B1-1 | DisplayName e.g. CarparkMV-COsensor-1 | Postalcode_LocationName e.g. 700123_CarparkLevelB1 | 67 |
| Fast and Secure Access System (Smart Lock) | SensorType-Postalcode-AggregatorIdentifier Same as SensorId | SensorType-Vendor-Postalcode-GenericIdentifier e.g. SmartLock-CA-700123-SwitchRoom-Lock SmartLock-CA-700123-PumpRoom-Lock | DisplayName e.g. SmartLock-PumpRoom | Postalcode_LocationName e.g. 700123_SwitchRoom, 700123_PumpRoom, 700123_RoofTop | 67 |

<a id="pdf-page-66"></a>

<!-- Source PDF page 66 -->

<a id="pdf-page-67"></a>

<!-- Source PDF page 67 -->
