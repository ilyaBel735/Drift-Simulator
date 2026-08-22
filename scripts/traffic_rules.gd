class_name TrafficRules
extends RefCounted

enum LightState { RED, YELLOW, GREEN }

const GREEN_TIME := 6.0
const YELLOW_TIME := 2.0
const ALL_RED_TIME := 6.0
const CYCLE_TIME := 28.0


static func get_state(intersection: Vector2i, direction: Vector2i) -> int:
    if direction == Vector2i.ZERO:
        return LightState.RED

    var h := int(abs(hash("%d|%d|traffic_phase" % [intersection.x, intersection.y])))
    var offset := float(h % 8)

    var t := fposmod(Time.get_ticks_msec() / 1000.0 + offset, CYCLE_TIME)

    var ns := direction.y != 0

    var ns_green_end := GREEN_TIME
    var ns_yellow_end := ns_green_end + YELLOW_TIME

    var ew_green_start := ns_yellow_end + ALL_RED_TIME
    var ew_green_end := ew_green_start + GREEN_TIME
    var ew_yellow_end := ew_green_end + YELLOW_TIME

    if ns:
        if t < ns_green_end:
            return LightState.GREEN

        if t < ns_yellow_end:
            return LightState.YELLOW

        return LightState.RED
    else:
        if t >= ew_green_start and t < ew_green_end:
            return LightState.GREEN

        if t >= ew_green_end and t < ew_yellow_end:
            return LightState.YELLOW

        return LightState.RED


static func are_all_red(intersection: Vector2i) -> bool:
    var ew_state := get_state(intersection, Vector2i(1, 0))
    var ns_state := get_state(intersection, Vector2i(0, 1))

    return ew_state == LightState.RED and ns_state == LightState.RED