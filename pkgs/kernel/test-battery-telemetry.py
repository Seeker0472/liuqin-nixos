#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the patched battery getter against recorded firmware units.

Compile the driver's actual C getter, property map and property list with a
small transport stub. The fixture values come from liuqin's stock sysfs and
the 2026-11-13 charging capture; they are deliberately not derived from the
driver's constants or conversion code.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


def block(source, prefix, ending):
    start = source.index(prefix)
    end = source.index(ending, start) + len(ending)
    return source[start:end] + "\n"


def main():
    tree = Path(sys.argv[1])
    source = (tree / "drivers/power/supply/qcom_battmgr.c").read_text()
    header = (tree / "include/linux/power_supply.h").read_text()
    declarations = "\n".join([
        block(header, "enum power_supply_property {", "\n};"),
        block(source, "enum qcom_battmgr_variant {", "\n};"),
        block(source, "enum qcom_battmgr_unit {", "\n};"),
        block(source, "struct qcom_battmgr_info {", "\n};"),
        block(source, "struct qcom_battmgr_status {", "\n};"),
    ])
    functions = "\n".join(
        block(source, prefix, "\n}") for prefix in [
            "static unsigned int qcom_battmgr_bat_fw_property(",
            "static int qcom_battmgr_bat_sm8350_update(",
            "static int qcom_battmgr_bat_charge_counter(",
            "static int qcom_battmgr_bat_get_property(",
        ]
    )
    arrays = "\n".join(
        block(source, prefix, "\n};") for prefix in [
            "static const u8 sm8350_bat_prop_map[] =",
            "static const enum power_supply_property sm8350_bat_props[] =",
            "static const enum power_supply_property sm8475_bat_props[] =",
            "static const enum power_supply_property sm8550_bat_props[] =",
        ]
    )
    # The property map precedes the functions that use it.
    constants = "\n".join(line for line in source.splitlines()
                          if line.startswith("#define BATT"))
    program = r'''
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint8_t u8;
typedef int32_t s32;
typedef uint32_t u32;
#define MILLI 1000UL
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define check_mul_overflow(a, b, out) __builtin_mul_overflow(a, b, out)
''' + constants + "\n" + declarations + r'''
struct mutex { int unused; };
struct qcom_battmgr {
    enum qcom_battmgr_variant variant;
    enum qcom_battmgr_unit unit;
    bool service_up;
    struct mutex lock;
    struct qcom_battmgr_info info;
    struct qcom_battmgr_status status;
};
struct power_supply { struct qcom_battmgr *data; };
union power_supply_propval { int intval; const char *strval; };
static void mutex_lock(struct mutex *lock) { (void)lock; }
static void mutex_unlock(struct mutex *lock) { (void)lock; }
static struct qcom_battmgr *power_supply_get_drvdata(struct power_supply *psy)
{ return psy->data; }
static int qcom_battmgr_bat_sc8280xp_update(struct qcom_battmgr *battmgr,
                                         enum power_supply_property psp)
{ (void)battmgr; (void)psp; return 0; }

static int requests, last_property, transport_error;
static u32 counter = 4688;
static s32 current = -10843000;
static int qcom_battmgr_request_property(struct qcom_battmgr *battmgr,
                                        int opcode, int property, u32 value)
{
    (void)value;
    requests++;
    last_property = property;
    assert(opcode == 0x30);
    if (transport_error)
        return transport_error;

    if (battmgr->variant == QCOM_BATTMGR_SM8475) {
        switch (property) {
        case 15: battmgr->info.charge_count = counter; break;
        case 17: battmgr->info.design_capacity = 8600000; break;
        case 18: battmgr->info.last_full_capacity = 7827000; break;
        case 4: battmgr->status.percent = 66; break;
        case 7: battmgr->status.voltage_now = 4389000; break;
        case 9: battmgr->status.current_now = current; break;
        default: return -EINVAL;
        }
    } else {
        switch (property) {
        case 14: battmgr->info.charge_count = counter; break;
        case 22: battmgr->status.power_now = 12345000; break;
        default: return -EINVAL;
        }
    }
    return 0;
}
''' + arrays + "\n" + functions + r'''
static void expect(struct power_supply *psy, enum power_supply_property psp,
                   int error, int value)
{
    union power_supply_propval got = { .intval = INT_MIN };
    assert(qcom_battmgr_bat_get_property(psy, psp, &got) == error);
    if (!error)
        assert(got.intval == value);
}
static bool contains(const enum power_supply_property *props, size_t count,
                     enum power_supply_property psp)
{
    for (size_t i = 0; i < count; i++)
        if (props[i] == psp)
            return true;
    return false;
}
int main(void)
{
    /* Leave the unit zero-initialised, as on the real property protocol. */
    struct qcom_battmgr battmgr = {
        .variant = QCOM_BATTMGR_SM8475, .service_up = true,
    };
    struct power_supply psy = { .data = &battmgr };
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN, 0, 8600000);
    assert(last_property == 17);
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_FULL, 0, 7827000);
    assert(last_property == 18);
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_NOW, 0, 4688000);
    assert(last_property == 15);
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_COUNTER, 0, 4688000);
    counter = 4703;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_NOW, 0, 4703000);
    counter = 0;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_NOW, 0, 0);
    counter = (u32)-1;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_COUNTER, 0, -1000);
    counter = 2147483;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_COUNTER, 0, 2147483000);
    counter = 2147484;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_COUNTER, -ERANGE, 0);
    counter = (u32)-2147484;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_COUNTER, -ERANGE, 0);
    expect(&psy, POWER_SUPPLY_PROP_CURRENT_NOW, 0, 10843000);
    current = 250000;
    expect(&psy, POWER_SUPPLY_PROP_CURRENT_NOW, 0, -250000);
    expect(&psy, POWER_SUPPLY_PROP_VOLTAGE_NOW, 0, 4389000);
    expect(&psy, POWER_SUPPLY_PROP_CAPACITY, 0, 66);

    const enum power_supply_property unreliable[] = {
        POWER_SUPPLY_PROP_POWER_NOW,
        POWER_SUPPLY_PROP_TIME_TO_EMPTY_AVG,
        POWER_SUPPLY_PROP_TIME_TO_FULL_AVG,
    };
    requests = 0;
    for (size_t i = 0; i < ARRAY_SIZE(unreliable); i++) {
        assert(!contains(sm8475_bat_props, ARRAY_SIZE(sm8475_bat_props),
                         unreliable[i]));
        assert(contains(sm8350_bat_props, ARRAY_SIZE(sm8350_bat_props),
                        unreliable[i]));
        assert(contains(sm8550_bat_props, ARRAY_SIZE(sm8550_bat_props),
                        unreliable[i]));
        expect(&psy, unreliable[i], -ENODATA, 0);
    }
    assert(requests == 0);
    assert(contains(sm8475_bat_props, ARRAY_SIZE(sm8475_bat_props),
                    POWER_SUPPLY_PROP_CHARGE_NOW));
    for (size_t i = 0; i < ARRAY_SIZE(sm8350_bat_props); i++)
        if (!contains(unreliable, ARRAY_SIZE(unreliable), sm8350_bat_props[i]))
            assert(contains(sm8475_bat_props, ARRAY_SIZE(sm8475_bat_props),
                            sm8350_bat_props[i]));

    battmgr.service_up = false;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_NOW, -EAGAIN, 0);
    assert(requests == 0);
    battmgr.service_up = true;
    transport_error = -ETIMEDOUT;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_NOW, -ETIMEDOUT, 0);
    transport_error = 0;

    /* Other protocols already use uAh or uWh and must keep their units. */
    battmgr.variant = QCOM_BATTMGR_SM8350;
    counter = 4688000;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_COUNTER, 0, 4688000);
    assert(last_property == 14);
    expect(&psy, POWER_SUPPLY_PROP_POWER_NOW, 0, 12345000);
    battmgr.variant = QCOM_BATTMGR_SC8280XP;
    battmgr.status.capacity = 12345000;
    expect(&psy, POWER_SUPPLY_PROP_ENERGY_NOW, 0, 12345000);
    battmgr.unit = QCOM_BATTMGR_UNIT_mAh;
    expect(&psy, POWER_SUPPLY_PROP_CHARGE_NOW, 0, 12345000);
    puts("battery telemetry: firmware units, property map, errors and protocol isolation passed");
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="battmgr-telemetry-") as scratch:
        fixture = Path(scratch) / "fixture.c"
        fixture.write_text(program)
        binary = Path(scratch) / "fixture"
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
            "-std=gnu11", "-Wall", "-Wextra", "-Werror",
            str(fixture), "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
