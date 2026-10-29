pragma Singleton

import QtQuick
import Quickshell

// Material Symbols for Home Assistant entities, by domain and state (Home
// Assistant's own icons are Material Design Icons, which the shell doesn't
// have), and what counts as "on".
Singleton {
    readonly property var byDomain: ({
            light: ["lightbulb", "light_off"],
            switch: ["toggle_on", "toggle_off"],
            input_boolean: ["toggle_on", "toggle_off"],
            fan: ["mode_fan", "mode_fan_off"],
            lock: ["lock", "lock_open"],
            cover: ["blinds", "blinds_closed"],
            climate: ["thermostat", "thermostat"],
            media_player: ["speaker", "speaker"],
            camera: ["videocam", "videocam_off"],
            button: ["radio_button_checked", "radio_button_checked"],
            input_button: ["radio_button_checked", "radio_button_checked"],
            scene: ["palette", "palette"],
            script: ["play_circle", "play_circle"],
            automation: ["smart_toy", "smart_toy"],
            sensor: ["sensors", "sensors"],
            binary_sensor: ["sensors", "sensors_off"],
            person: ["person", "person_off"],
            device_tracker: ["location_on", "location_off"],
            vacuum: ["vacuum", "vacuum"],
            weather: ["partly_cloudy_day", "partly_cloudy_day"],
            sun: ["wb_sunny", "bedtime"],
            alarm_control_panel: ["shield", "remove_moderator"],
            update: ["system_update", "system_update"],
            number: ["tune", "tune"],
            select: ["list", "list"]
        })

    // Sensors by what they measure
    readonly property var byDeviceClass: ({
            temperature: "thermostat",
            humidity: "humidity_percentage",
            power: "bolt",
            energy: "electric_meter",
            battery: "battery_full",
            illuminance: "light_mode",
            motion: "directions_run",
            occupancy: "sensor_occupied",
            door: "door_front",
            window: "window",
            moisture: "water_drop",
            pressure: "compress",
            co2: "co2",
            voltage: "electric_bolt",
            current: "electric_bolt"
        })

    function isOn(state: string): bool {
        return ["on", "open", "opening", "unlocked", "playing", "home", "active", "heat", "cool", "auto"].includes(state);
    }

    // Domains that toggle, press or run when you tap them
    function isActionable(entityId: string): bool {
        return ["light", "switch", "input_boolean", "fan", "lock", "cover", "button", "input_button", "scene", "script", "automation", "media_player"].includes(entityId.split(".")[0]);
    }

    function iconFor(entityId: string, entity: var): string {
        const domain = entityId.split(".")[0];
        const dc = entity?.attributes?.device_class;
        if (dc && byDeviceClass[dc] && ["sensor", "binary_sensor"].includes(domain))
            return byDeviceClass[dc];
        const pair = byDomain[domain] ?? ["home_iot_device", "home_iot_device"];
        return !entity || isOn(entity.state) || !["light", "switch", "input_boolean", "fan", "binary_sensor", "person", "device_tracker", "camera"].includes(domain) ? pair[0] : pair[1];
    }

    // The state as people read it: "21.5 °C", "On", "Locked"
    function stateText(entity: var): string {
        if (!entity)
            return "…";
        // Timestamps as Home Assistant shows them: the local time, the date too
        // when it isn't today
        if (entity.attributes?.device_class === "timestamp") {
            const d = new Date(entity.state);
            if (!isNaN(d.getTime()))
                return d.toDateString() === new Date().toDateString() ? Qt.formatTime(d, "hh:mm") : Qt.formatDateTime(d, "d MMM hh:mm");
        }
        const unit = entity.attributes?.unit_of_measurement;
        if (unit)
            return `${entity.state} ${unit}`;
        const s = String(entity.state ?? "");
        return s.length > 0 ? s[0].toUpperCase() + s.slice(1).replace(/_/g, " ") : "";
    }
}
