local _, GGM = ...

GGM.SCHEMA_VERSION = 1

GGM.TRACKED_SLOTS = {
    { key = "HEAD", inventoryName = "HeadSlot" },
    { key = "NECK", inventoryName = "NeckSlot" },
    { key = "SHOULDER", inventoryName = "ShoulderSlot" },
    { key = "BACK", inventoryName = "BackSlot" },
    { key = "CHEST", inventoryName = "ChestSlot" },
    { key = "WRIST", inventoryName = "WristSlot" },
    { key = "HANDS", inventoryName = "HandsSlot" },
    { key = "WAIST", inventoryName = "WaistSlot" },
    { key = "LEGS", inventoryName = "LegsSlot" },
    { key = "FEET", inventoryName = "FeetSlot" },
    { key = "FINGER_1", inventoryName = "Finger0Slot" },
    { key = "FINGER_2", inventoryName = "Finger1Slot" },
    { key = "TRINKET_1", inventoryName = "Trinket0Slot" },
    { key = "TRINKET_2", inventoryName = "Trinket1Slot" },
    { key = "MAIN_HAND", inventoryName = "MainHandSlot" },
    { key = "OFF_HAND", inventoryName = "SecondaryHandSlot" },
}
