//! The camera's own controls (zoom, focus, white balance, image tuning) over
//! V4L2 ioctls. These work while anyone is streaming, PipeWire included.

use serde_json::{Value, json};
use v4l::control::{Control, Description, Flags, MenuItem, Type, Value as CVal};

fn kind(t: Type) -> &'static str {
    match t {
        Type::Integer | Type::Integer64 => "int",
        Type::Boolean => "bool",
        Type::Menu | Type::IntegerMenu => "menu",
        Type::Button => "button",
        _ => "other",
    }
}

/// Control names as V4L2 reports them, made into stable keys: "Zoom, Absolute" -> "zoom_absolute"
fn key(name: &str) -> String {
    let mut k = String::new();
    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            k.push(c.to_ascii_lowercase());
        } else if !k.ends_with('_') && !k.is_empty() {
            k.push('_');
        }
    }
    k.trim_end_matches('_').to_string()
}

pub fn list(device: &str) -> anyhow::Result<Value> {
    let dev = v4l::Device::with_path(device)?;
    let mut out = vec![];
    for d in dev.query_controls()? {
        if matches!(d.typ, Type::CtrlClass) || d.flags.contains(Flags::DISABLED) {
            continue;
        }
        let value = match dev.control(d.id) {
            Ok(c) => match c.value {
                CVal::Integer(v) => json!(v),
                CVal::Boolean(b) => json!(b),
                _ => Value::Null,
            },
            Err(_) => Value::Null,
        };
        out.push(describe(&d, value));
    }
    Ok(Value::Array(out))
}

fn describe(d: &Description, value: Value) -> Value {
    let menu: Vec<Value> = d
        .items
        .as_ref()
        .map(|items| {
            items
                .iter()
                .map(|(i, item)| match item {
                    MenuItem::Name(n) => json!({ "value": i, "label": n }),
                    MenuItem::Value(v) => json!({ "value": i, "label": v.to_string() }),
                })
                .collect()
        })
        .unwrap_or_default();
    json!({
        "id": d.id,
        "key": key(&d.name),
        "name": d.name,
        "type": kind(d.typ),
        "min": d.minimum,
        "max": d.maximum,
        "step": d.step,
        "default": d.default,
        "value": value,
        // e.g. white balance temperature while automatic white balance is on
        "inactive": d.flags.contains(Flags::INACTIVE),
        "menu": menu,
    })
}

pub fn set(device: &str, name: &str, value: &Value) -> anyhow::Result<()> {
    let dev = v4l::Device::with_path(device)?;
    let d = dev
        .query_controls()?
        .into_iter()
        .find(|d| key(&d.name) == name || d.name == name || d.id.to_string() == name)
        .ok_or_else(|| anyhow::anyhow!("no control {name:?}"))?;
    let v = match d.typ {
        Type::Boolean => CVal::Boolean(
            value
                .as_bool()
                .or_else(|| value.as_i64().map(|i| i != 0))
                .unwrap_or(false),
        ),
        _ => {
            let v = value
                .as_i64()
                .or_else(|| value.as_f64().map(|f| f.round() as i64))
                .unwrap_or(d.default);
            CVal::Integer(v.clamp(d.minimum, d.maximum))
        }
    };
    dev.set_control(Control { id: d.id, value: v })?;
    Ok(())
}
