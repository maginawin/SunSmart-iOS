#!/usr/bin/env python3
# Standalone Python 3 example; synthetic data, no SDK dependency.
import base64
import json

FIELDS = [
    ("year", 4, 7), ("month", 11, 12), ("day", 23, 5),
    ("hour", 28, 5), ("minute", 33, 6), ("second", 39, 6),
    ("dayOfWeek", 45, 7), ("action", 52, 4),
    ("transitionTimeRaw", 56, 8), ("sceneNumber", 64, 16),
]
DEFAULT_CLEAR = dict(year=100, month=0, day=0, hour=24, minute=60,
                     second=60, dayOfWeek=0, action=15,
                     transitionTimeRaw=63, sceneNumber=0)

def pack_entry(slot, entry):
    if type(slot) is not int or not 0 <= slot <= 15:
        raise ValueError("invalid physical slot")
    for field, offset, width in FIELDS:
        item = entry[field]
        if type(item) is not int or not 0 <= item < (1 << width):
            raise ValueError(field)
    if entry["year"] > 100 or entry["hour"] > 25:
        raise ValueError("reserved time value")
    if entry["action"] not in (0, 1, 2, 15):
        raise ValueError("reserved action")
    # 具体算法：各字段移到固定位置，再组合成80位整数。
    value = (
        slot
        | (entry["year"] << 4)
        | (entry["month"] << 11)
        | (entry["day"] << 23)
        | (entry["hour"] << 28)
        | (entry["minute"] << 33)
        | (entry["second"] << 39)
        | (entry["dayOfWeek"] << 45)
        | (entry["action"] << 52)
        | (entry["transitionTimeRaw"] << 56)
        | (entry["sceneNumber"] << 64)
    )
    return value.to_bytes(10, byteorder="little")

def encode_entries(entries):
    # None 表示未知，应由外层省略 Model；不能编码成空表。
    if not isinstance(entries, dict) or len(entries) > 16:
        raise ValueError("expected known slot dictionary")
    payload = b"".join(pack_entry(slot, entries[slot])
                       for slot in sorted(entries))
    return base64.b64encode(payload).decode("ascii")

def decode_entries(text):
    payload = base64.b64decode(text, validate=True)
    if len(payload) > 160 or len(payload) % 10:
        raise ValueError("invalid byte length")
    result = {}
    for start in range(0, len(payload), 10):
        chunk = payload[start:start + 10]
        value = int.from_bytes(chunk, byteorder="little")
        slot = value & 15
        if slot in result:
            raise ValueError("duplicate slot")
        entry = {field: (value >> offset) & ((1 << width) - 1)
                 for field, offset, width in FIELDS}
        pack_entry(slot, entry)  # 对新生成数据做取值校验。
        result[slot] = entry
    return result

def neutral_projection(model_entries_in_sdk_order):
    result = {}
    for entries in model_entries_in_sdk_order:
        if entries is None:  # 未知；不能据此推断该 Model 为空。
            continue
        for slot, entry in entries.items():
            if entry != DEFAULT_CLEAR:
                result[slot] = entry  # 后遍历的有效同槽条目覆盖前者。
    return result

def readable_legacy(slot, entry):
    result = {field: entry[field] for field, _, _ in FIELDS
              if field != "transitionTimeRaw"}
    raw = entry["transitionTimeRaw"]
    steps, resolution = raw & 63, (0.1, 1, 10, 600)[raw >> 6]
    result["id"] = slot
    result["transitionTime"] = 0 if steps == 63 else int(steps * resolution)
    return result

def weekly_entry(*, enabled, hour, minute, day_of_week,
                 action, fade_seconds, scene_number=0):
    # 对应当前 App 的正常周重复定时；清理 slot 用 DEFAULT_CLEAR。
    if type(enabled) is not bool:
        raise ValueError("enabled must be bool")
    for name, value, low, high in (
        ("hour", hour, 0, 23), ("minute", minute, 0, 59),
        ("day_of_week", day_of_week, 1, 127),
        ("fade_seconds", fade_seconds, 0, 60),
        ("scene_number", scene_number, 0, 65535),
    ):
        if type(value) is not int or not low <= value <= high:
            raise ValueError(name)
    if type(action) is not int or action not in (0, 1, 2):
        raise ValueError("action must be Off=0, On=1 or Scene Recall=2")
    if (action == 2) != (scene_number != 0):
        raise ValueError("Scene Recall requires a nonzero scene_number")
    return dict(
        year=100 if enabled else 0, month=4095, day=0,
        hour=hour, minute=minute, second=0, dayOfWeek=day_of_week,
        action=action, transitionTimeRaw=(1 << 6) | fade_seconds,
        sceneNumber=scene_number,
    )

def build_node_fragment(identity, model_entries, legacy_entries):
    # 这里只生成要并回完整 Node 的字段，不生成完整 Space／密钥／Composition。
    models = [
        dict(elementAddress=address, modelId="1207",
             entriesData=encode_entries(entries))
        for address, entries in model_entries if entries is not None
    ]
    snapshot = dict(schemaVersion=1, **identity, models=models,
                    legacyEntriesData=encode_entries(legacy_entries))
    return dict(
        uuid=identity["nodeUUID"], unicastAddress=identity["unicastAddress"],
        schedules=[readable_legacy(slot, legacy_entries[slot])
                   for slot in sorted(legacy_entries)],
        custProps=dict(schedulerModelStates=snapshot),
    )

def demo_node_fragment():
    # 1. 三条不同的业务定时；示例节点普通 Model=0100，LC Model=0101。
    on = weekly_entry(enabled=True, hour=8, minute=0, day_of_week=31,
                      action=1, fade_seconds=5)
    disabled_off = weekly_entry(enabled=False, hour=22, minute=0,
                                day_of_week=127, action=0, fade_seconds=0)
    recall = weekly_entry(enabled=True, hour=18, minute=0, day_of_week=127,
                          action=2, fade_seconds=5, scene_number=10)

    # 2. 单条编码调用与预期值；生成这些 bytes 不等于设备已成功配置。
    raw = pack_entry(0, on)
    assert len(raw) == 10
    assert raw.hex().upper() == "40FE7F8000E013450000"
    assert encode_entries({0: on}) == "QP5/gADgE0UAAA=="
    assert decode_entries(encode_entries({0: on})) == {0: on}

    # 3. 以下仅假设网关已确认这些表内容；真实服务用实际读回／确认结果。
    model_entries = [
        ("0100", {1: disabled_off, 2: recall}),
        ("0101", {0: on}),
    ]
    # 本例 slot 互不冲突，采用中性兼容表；App 上传的旧 legacy 应原样保留。
    legacy_entries = neutral_projection([entries for _, entries in model_entries])
    identity = dict(
        nodeUUID="00000000-0000-4000-8000-000000000001",
        unicastAddress="0100",
        deviceKeyFingerprint="0a4a91ae6e293dee6cb98cf621ae487d781966980403b7b0472e7807bd676c3b",
    )
    result = build_node_fragment(identity, model_entries, legacy_entries)

    # 4. 停用保留 slot1；默认清理条目可编码，清理确认后的兼容表不保留它。
    assert legacy_entries[1]["year"] == 0
    assert encode_entries({2: DEFAULT_CLEAR}) == "QgYAgHke8D8AAA=="
    assert neutral_projection([{2: DEFAULT_CLEAR}]) == {}
    assert encode_entries({}) == ""
    unknown = build_node_fragment(identity, [("0100", None), ("0101", {})], {})
    assert unknown["custProps"]["schedulerModelStates"]["models"] == [
        {"elementAddress": "0101", "modelId": "1207", "entriesData": ""}
    ]
    return result

if __name__ == "__main__":
    print(json.dumps(demo_node_fragment(), ensure_ascii=False, indent=2))
