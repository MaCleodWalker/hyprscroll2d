return {
    -- Optionally pin Hyprscroll2D to one workspace at startup. Leave unset to
    -- enable it per workspace by rotating the layout with Super+L.
    -- workspace = 9,

    -- Keep a visible strip of neighboring cells around the focused window.
    peek_x = 48,
    peek_y = 48,
    gap_x = 12,
    gap_y = 12,

    -- Draw live scaled thumbnails of each window in the overview (needs the
    -- Omarchy shell service). Set to false to resize the real windows instead.
    overview_thumbnails = true,

    -- Smallest a window cell may shrink to in the overview, as a fraction of
    -- the viewport. Larger workspaces scroll instead of shrinking further.
    overview_min_width = 0.25,
    overview_min_height = 0.25,

    -- Window dimensions are fractions of one grid cell. The largest preset
    -- still preserves the configured edge peeks.
    width_steps = { 0.50, 0.67, 0.85, 1.00 },
    height_steps = { 0.50, 0.67, 0.85, 1.00 },
    default_width_step = 2,
    default_height_step = 3,
}
