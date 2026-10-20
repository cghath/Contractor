"""Writes themes/contractor_ui.tres (the shared UI theme, docs/ui_audit.md) from one palette, so every state's
colours and paddings stay consistent. Run with Python 3: python tools/gen_ui_theme.py <repo root>."""
import sys, os

ROOT = sys.argv[1]

# Palette (keep in step with scripts/ui/ui_kit.gd).
TEXT = (0.92, 0.93, 0.89, 1)
TEXT_BRIGHT = (0.97, 0.97, 0.94, 1)
TEXT_DIM = (0.70, 0.73, 0.67, 1)
TEXT_OFF = (0.50, 0.52, 0.48, 1)
ACCENT = (0.93, 0.69, 0.27, 1)
ACCENT_HOT = (1.0, 0.80, 0.42, 1)
GOOD = (0.50, 0.80, 0.45, 1)
WARN = (0.95, 0.47, 0.38, 1)
INK = (0.06, 0.07, 0.06, 1)

subs = []
def c(t, a=None):
    r, g, b, aa = t
    if a is not None:
        aa = a
    return "Color(%s, %s, %s, %s)" % tuple(round(v, 3) for v in (r, g, b, aa))

def box(id_, bg=None, border=None, bw=(0, 0, 0, 0), radius=(0, 0, 0, 0), margins=None, shadow=None,
        expand=None, draw_center=True, aa=True, skew=None):
    lines = ['[sub_resource type="StyleBoxFlat" id="%s"]' % id_]
    if margins:
        for side, v in zip(("left", "top", "right", "bottom"), margins):
            lines.append("content_margin_%s = %s" % (side, float(v)))
    if bg is not None:
        lines.append("bg_color = %s" % bg)
    if not draw_center:
        lines.append("draw_center = false")
    for side, v in zip(("left", "top", "right", "bottom"), bw):
        if v:
            lines.append("border_width_%s = %d" % (side, v))
    if border is not None:
        lines.append("border_color = %s" % border)
    for corner, v in zip(("top_left", "top_right", "bottom_right", "bottom_left"), radius):
        if v:
            lines.append("corner_radius_%s = %d" % (corner, v))
    if expand:
        for side, v in zip(("left", "top", "right", "bottom"), expand):
            lines.append("expand_margin_%s = %s" % (side, float(v)))
    if shadow:
        lines.append("shadow_color = %s" % shadow[0])
        lines.append("shadow_size = %d" % shadow[1])
        if len(shadow) > 2:
            lines.append("shadow_offset = Vector2(%s, %s)" % shadow[2])
    if not aa:
        lines.append("anti_aliasing = false")
    subs.append("\n".join(lines))
    return id_

R = (6, 6, 6, 6)
r4 = (4, 4, 4, 4)
ALL1 = (1, 1, 1, 1)
BTN_M = (14, 7, 14, 7)

# Panels: dark olive glass with a hairline edge and a soft shadow for depth.
box("panel", bg="Color(0.065, 0.075, 0.065, 0.93)", border="Color(0.30, 0.33, 0.27, 0.95)", bw=ALL1, radius=R,
    margins=(18, 16, 18, 16), shadow=("Color(0, 0, 0, 0.35)", 10, (0, 3)))
box("panel_solid", bg="Color(0.085, 0.095, 0.085, 1)", border="Color(0.30, 0.33, 0.27, 1)", bw=ALL1, radius=R,
    margins=(18, 16, 18, 16), shadow=("Color(0, 0, 0, 0.45)", 12, (0, 4)))
# A card inside a panel (a section, a help box): a shade lighter, no shadow.
box("card", bg="Color(0.12, 0.135, 0.115, 0.85)", border="Color(0.24, 0.27, 0.22, 1)", bw=ALL1, radius=R,
    margins=(12, 10, 12, 10))
box("help", bg="Color(0.10, 0.11, 0.095, 0.97)", border=c(ACCENT, 0.55), bw=(3, 1, 1, 1), radius=R,
    margins=(14, 12, 14, 12))
box("tooltip", bg="Color(0.05, 0.06, 0.05, 0.97)", border=c(ACCENT, 0.6), bw=ALL1, radius=r4,
    margins=(10, 7, 10, 7), shadow=("Color(0, 0, 0, 0.45)", 6, (0, 2)))

# Buttons.
box("button_normal", bg="Color(0.155, 0.175, 0.15, 0.96)", border="Color(0.28, 0.31, 0.26, 1)", bw=ALL1, radius=R, margins=BTN_M)
box("button_hover", bg="Color(0.215, 0.24, 0.2, 1)", border=c(ACCENT, 0.8), bw=ALL1, radius=R, margins=BTN_M)
box("button_pressed", bg="Color(0.36, 0.27, 0.11, 1)", border=c(ACCENT), bw=ALL1, radius=R, margins=BTN_M)
box("button_disabled", bg="Color(0.11, 0.12, 0.11, 0.75)", border="Color(0.19, 0.21, 0.18, 1)", bw=ALL1, radius=R, margins=BTN_M)
box("focus", draw_center=False, border=c(ACCENT_HOT), bw=(2, 2, 2, 2), radius=(7, 7, 7, 7), expand=(2, 2, 2, 2))
# The primary action (Deploy, Confirm): amber with dark text.
box("accent_normal", bg=c(ACCENT), border=c(ACCENT_HOT), bw=ALL1, radius=R, margins=BTN_M)
box("accent_hover", bg=c(ACCENT_HOT), border="Color(1, 0.9, 0.65, 1)", bw=ALL1, radius=R, margins=BTN_M)
box("accent_pressed", bg="Color(0.78, 0.55, 0.18, 1)", border=c(ACCENT_HOT), bw=ALL1, radius=R, margins=BTN_M)
# A dangerous action (Sell, Discard): red-orange edge.
box("danger_normal", bg="Color(0.2, 0.12, 0.1, 0.96)", border=c(WARN, 0.7), bw=ALL1, radius=R, margins=BTN_M)
box("danger_hover", bg="Color(0.3, 0.15, 0.12, 1)", border=c(WARN), bw=ALL1, radius=R, margins=BTN_M)
box("danger_pressed", bg="Color(0.45, 0.18, 0.13, 1)", border=c(WARN), bw=ALL1, radius=R, margins=BTN_M)
# A flat row (a list entry you can click): no box until hovered.
box("row_normal", bg="Color(1, 1, 1, 0)", radius=r4, margins=(8, 4, 8, 4))
box("row_hover", bg=c(ACCENT, 0.16), border=c(ACCENT, 0.45), bw=(2, 0, 0, 0), radius=r4, margins=(8, 4, 8, 4))
box("row_pressed", bg=c(ACCENT, 0.3), border=c(ACCENT), bw=(2, 0, 0, 0), radius=r4, margins=(8, 4, 8, 4))
# The small round "?" help button.
box("help_button", bg="Color(0.155, 0.175, 0.15, 0.96)", border=c(ACCENT, 0.7), bw=ALL1, radius=(14, 14, 14, 14), margins=(9, 3, 9, 3))
box("help_button_hover", bg=c(ACCENT, 0.3), border=c(ACCENT_HOT), bw=ALL1, radius=(14, 14, 14, 14), margins=(9, 3, 9, 3))

# Fields, lists, menus.
box("field", bg="Color(0.035, 0.045, 0.035, 0.96)", border="Color(0.28, 0.31, 0.26, 1)", bw=ALL1, radius=r4, margins=(10, 6, 10, 6))
box("field_focus", draw_center=False, border=c(ACCENT_HOT), bw=(2, 2, 2, 2), radius=r4)
box("list_panel", bg="Color(0.04, 0.05, 0.04, 0.9)", border="Color(0.24, 0.27, 0.22, 1)", bw=ALL1, radius=r4, margins=(6, 6, 6, 6))
box("list_hover", bg=c(ACCENT, 0.12), radius=r4)
box("list_selected", bg=c(ACCENT, 0.28), border=c(ACCENT, 0.8), bw=(2, 0, 0, 0), radius=r4)
box("popup_panel", bg="Color(0.07, 0.08, 0.07, 0.98)", border="Color(0.33, 0.36, 0.3, 1)", bw=ALL1, radius=R,
    margins=(6, 6, 6, 6), shadow=("Color(0, 0, 0, 0.45)", 8, (0, 3)))
box("popup_hover", bg=c(ACCENT, 0.22), border=c(ACCENT, 0.7), bw=(2, 0, 0, 0), radius=r4, margins=(8, 4, 8, 4))
box("separator", bg="Color(0.3, 0.33, 0.27, 0.8)", margins=(0, 4, 0, 4))

# Tabs: an amber underline on the open one.
box("tab_selected", bg="Color(0.13, 0.145, 0.125, 1)", border=c(ACCENT), bw=(0, 0, 0, 3), radius=(6, 6, 0, 0), margins=(16, 8, 16, 7))
box("tab_unselected", bg="Color(0.075, 0.085, 0.075, 0.92)", radius=(6, 6, 0, 0), margins=(16, 8, 16, 8))
box("tab_hover", bg="Color(0.19, 0.21, 0.18, 1)", border=c(ACCENT, 0.45), bw=(0, 0, 0, 2), radius=(6, 6, 0, 0), margins=(16, 8, 16, 8))
box("tab_panel", bg="Color(0.11, 0.125, 0.105, 1)", border="Color(0.24, 0.27, 0.22, 1)", bw=ALL1, radius=(0, 6, 6, 6), margins=(14, 14, 14, 14))

# Bars, sliders, scroll bars.
box("bar_fill", bg=c(ACCENT), radius=r4)
box("bar_back", bg="Color(0.035, 0.045, 0.035, 0.96)", border="Color(0.28, 0.31, 0.26, 1)", bw=ALL1, radius=r4)
box("key_chip", bg=c(ACCENT), radius=r4, margins=(7, 1, 7, 2))
box("slider_track", bg="Color(0.035, 0.045, 0.035, 1)", border="Color(0.28, 0.31, 0.26, 1)", bw=ALL1, radius=r4, margins=(0, 3, 0, 3))
box("slider_fill", bg=c(ACCENT, 0.85), radius=r4, margins=(0, 3, 0, 3))
box("slider_fill_hot", bg=c(ACCENT_HOT), radius=r4, margins=(0, 3, 0, 3))
box("scroll_track", bg="Color(0, 0, 0, 0.25)", radius=r4, margins=(4, 4, 4, 4))
box("scroll_grabber", bg="Color(0.4, 0.43, 0.37, 0.85)", radius=r4)
box("scroll_grabber_hot", bg=c(ACCENT, 0.85), radius=r4)

# HUD: a faint backing for HUD blocks over the 3D view.
box("hud_panel", bg="Color(0.03, 0.04, 0.03, 0.55)", border="Color(1, 1, 1, 0.06)", bw=ALL1, radius=R, margins=(12, 9, 12, 9))
box("hud_row_hot", bg=c(ACCENT, 0.22), border=c(ACCENT), bw=(3, 0, 0, 0), radius=r4, margins=(6, 0, 6, 0))
box("hud_row", bg="Color(1, 1, 1, 0)", radius=r4, margins=(6, 0, 6, 0))
box("hud_row_hover", bg="Color(1, 1, 1, 0.08)", border=c(ACCENT, 0.5), bw=(3, 0, 0, 0), radius=r4, margins=(6, 0, 6, 0))

S = lambda id_: 'SubResource("%s")' % id_

props = []
P = props.append
P('default_font = ExtResource("1_body")')
P("default_font_size = 16")
# Labels.
P("Label/colors/font_color = %s" % c(TEXT))
P("Label/colors/font_shadow_color = Color(0, 0, 0, 0.55)")
P("Label/colors/font_outline_color = Color(0, 0, 0, 0.8)")
P("Label/constants/shadow_offset_x = 1")
P("Label/constants/shadow_offset_y = 1")
P("Label/constants/line_spacing = 2")
def variation(name, base="Label", **kw):
    P('%s/base_type = &"%s"' % (name, base))
    for k, v in kw.items():
        P("%s/%s = %s" % (name, k.replace("__", "/"), v))
variation("HeadingLabel", colors__font_color=c(ACCENT), font_sizes__font_size=20, fonts__font='ExtResource("2_strong")')
variation("TitleLabel", colors__font_color=c(TEXT_BRIGHT), font_sizes__font_size=26, fonts__font='ExtResource("3_bold")')
variation("SubtitleLabel", colors__font_color=c(TEXT_DIM), font_sizes__font_size=16)
variation("HintLabel", colors__font_color=c(TEXT_DIM), font_sizes__font_size=14)
variation("WarnLabel", colors__font_color=c(WARN))
variation("GoodLabel", colors__font_color=c(GOOD))
variation("MutedLabel", colors__font_color=c(TEXT_DIM))
variation("StatLabel", colors__font_color=c(TEXT_BRIGHT), font_sizes__font_size=18, fonts__font='ExtResource("2_strong")')
variation("KeyLabel", colors__font_color=c(INK), colors__font_shadow_color="Color(0, 0, 0, 0)", font_sizes__font_size=14,
          fonts__font='ExtResource("3_bold")', styles__normal=S("key_chip"))
variation("AccentLabel", colors__font_color=c(ACCENT_HOT), fonts__font='ExtResource("2_strong")')
variation("HelpTitleLabel", colors__font_color=c(ACCENT), font_sizes__font_size=18, fonts__font='ExtResource("2_strong")')
# HUD text over the 3D view: a heavier weight and a black outline (UiKit.FONT_HUD*).
variation("HudLabel", colors__font_color=c(TEXT_BRIGHT), colors__font_outline_color="Color(0, 0, 0, 0.9)",
          colors__font_shadow_color="Color(0, 0, 0, 0)", constants__outline_size=5, font_sizes__font_size=20,
          fonts__font='ExtResource("2_strong")')
variation("HudSmallLabel", base="HudLabel", colors__font_color="Color(0.9, 0.91, 0.87, 1)", constants__outline_size=4,
          font_sizes__font_size=16)
variation("HudAlertLabel", base="HudLabel", colors__font_color=c(WARN), constants__outline_size=6, font_sizes__font_size=28,
          fonts__font='ExtResource("3_bold")')
variation("HudWarnLabel", base="HudLabel", colors__font_color=c(WARN))
variation("HudAccentLabel", base="HudLabel", colors__font_color=c(ACCENT))
variation("HudSmallWarnLabel", base="HudSmallLabel", colors__font_color=c(WARN))
# Rich text (ItemInfo, briefings): body text, a semibold for [b].
P("RichTextLabel/colors/default_color = %s" % c(TEXT))
P('RichTextLabel/fonts/bold_font = ExtResource("2_strong")')
P('RichTextLabel/fonts/normal_font = ExtResource("1_body")')
P("RichTextLabel/constants/line_separation = 2")
# Panels.
P("PanelContainer/styles/panel = %s" % S("panel"))
variation("HudPanel", base="PanelContainer", styles__panel=S("hud_panel"))
variation("SolidPanel", base="PanelContainer", styles__panel=S("panel_solid"))
variation("CardPanel", base="PanelContainer", styles__panel=S("card"))
variation("HelpPanel", base="PanelContainer", styles__panel=S("help"))
variation("HudRowHot", base="PanelContainer", styles__panel=S("hud_row_hot"))
variation("HudRow", base="PanelContainer", styles__panel=S("hud_row"))
variation("HudRowHover", base="PanelContainer", styles__panel=S("hud_row_hover"))
P("TooltipPanel/styles/panel = %s" % S("tooltip"))
P("TooltipLabel/colors/font_color = %s" % c(TEXT))
P("TooltipLabel/colors/font_shadow_color = Color(0, 0, 0, 0)")
P("TooltipLabel/font_sizes/font_size = 15")
# Buttons.
def button_type(name, normal, hover, pressed, disabled="button_disabled", font=None, colours=None):
    P("%s/styles/normal = %s" % (name, S(normal)))
    P("%s/styles/hover = %s" % (name, S(hover)))
    P("%s/styles/pressed = %s" % (name, S(pressed)))
    P("%s/styles/hover_pressed = %s" % (name, S(pressed)))
    P("%s/styles/disabled = %s" % (name, S(disabled)))
    P("%s/styles/focus = %s" % (name, S("focus")))
    if font:
        P("%s/fonts/font = %s" % (name, font))
    for k, v in (colours or {}).items():
        P("%s/colors/%s = %s" % (name, k, v))
BTN_COL = {"font_color": c(TEXT), "font_hover_color": "Color(1, 0.97, 0.88, 1)", "font_pressed_color": "Color(1, 0.95, 0.82, 1)",
           "font_focus_color": "Color(1, 0.97, 0.88, 1)", "font_hover_pressed_color": "Color(1, 0.95, 0.82, 1)",
           "font_disabled_color": c(TEXT_OFF)}
button_type("Button", "button_normal", "button_hover", "button_pressed", font='ExtResource("2_strong")', colours=BTN_COL)
P("Button/constants/h_separation = 8")
P("Button/constants/icon_max_width = 0")
variation("AccentButton", base="Button")
button_type("AccentButton", "accent_normal", "accent_hover", "accent_pressed",
            colours={"font_color": c(INK), "font_hover_color": c(INK), "font_pressed_color": c(INK), "font_focus_color": c(INK),
                     "font_hover_pressed_color": c(INK)})
variation("DangerButton", base="Button")
button_type("DangerButton", "danger_normal", "danger_hover", "danger_pressed")
variation("RowButton", base="Button")
button_type("RowButton", "row_normal", "row_hover", "row_pressed", disabled="row_normal")
variation("HelpButton", base="Button")
button_type("HelpButton", "help_button", "help_button_hover", "help_button_hover", colours={"font_color": c(ACCENT)})
button_type("OptionButton", "button_normal", "button_hover", "button_pressed", font='ExtResource("2_strong")', colours=BTN_COL)
P("CheckBox/colors/font_color = %s" % c(TEXT))
P("CheckBox/colors/font_hover_color = Color(1, 0.97, 0.88, 1)")
P("CheckBox/colors/font_pressed_color = %s" % c(TEXT))
P("CheckBox/colors/font_hover_pressed_color = Color(1, 0.97, 0.88, 1)")
P("CheckBox/colors/font_focus_color = Color(1, 0.97, 0.88, 1)")
P("CheckBox/styles/focus = %s" % S("focus"))
P("CheckBox/styles/hover = %s" % S("row_hover"))
P("CheckBox/styles/hover_pressed = %s" % S("row_hover"))
P("CheckBox/styles/normal = %s" % S("row_normal"))
P("CheckBox/styles/pressed = %s" % S("row_normal"))
P("CheckBox/constants/h_separation = 8")
# Fields.
P("LineEdit/colors/font_color = %s" % c(TEXT))
P("LineEdit/colors/font_placeholder_color = Color(0.6, 0.63, 0.57, 0.8)")
P("LineEdit/colors/font_uneditable_color = %s" % c(TEXT_DIM))
P("LineEdit/colors/caret_color = %s" % c(ACCENT_HOT))
P("LineEdit/colors/selection_color = %s" % c(ACCENT, 0.35))
P("LineEdit/styles/normal = %s" % S("field"))
P("LineEdit/styles/read_only = %s" % S("field"))
P("LineEdit/styles/focus = %s" % S("field_focus"))
# Lists and pop-up menus.
P("ItemList/colors/font_color = %s" % c(TEXT))
P("ItemList/colors/font_hovered_color = Color(1, 0.97, 0.88, 1)")
P("ItemList/colors/font_selected_color = Color(1, 0.97, 0.88, 1)")
P("ItemList/colors/guide_color = Color(1, 1, 1, 0.05)")
P("ItemList/constants/v_separation = 6")
P("ItemList/styles/panel = %s" % S("list_panel"))
P("ItemList/styles/focus = %s" % S("field_focus"))
P("ItemList/styles/hovered = %s" % S("list_hover"))
P("ItemList/styles/selected = %s" % S("list_selected"))
P("ItemList/styles/selected_focus = %s" % S("list_selected"))
P("ItemList/styles/cursor = %s" % S("field_focus"))
P("ItemList/styles/cursor_unfocused = %s" % S("field_focus"))
P("PopupMenu/colors/font_color = %s" % c(TEXT))
P("PopupMenu/colors/font_hover_color = Color(1, 0.97, 0.88, 1)")
P("PopupMenu/colors/font_disabled_color = %s" % c(TEXT_OFF))
P("PopupMenu/colors/font_separator_color = %s" % c(TEXT_DIM))
P("PopupMenu/constants/v_separation = 8")
P("PopupMenu/styles/panel = %s" % S("popup_panel"))
P("PopupMenu/styles/hover = %s" % S("popup_hover"))
P("PopupMenu/styles/separator = %s" % S("separator"))
P("HSeparator/styles/separator = %s" % S("separator"))
P("HSeparator/constants/separation = 10")
# Tabs.
P("TabContainer/colors/font_selected_color = Color(1, 0.97, 0.88, 1)")
P("TabContainer/colors/font_unselected_color = %s" % c(TEXT_DIM))
P("TabContainer/colors/font_hovered_color = %s" % c(TEXT))
P('TabContainer/fonts/font = ExtResource("2_strong")')
P("TabContainer/styles/tab_selected = %s" % S("tab_selected"))
P("TabContainer/styles/tab_unselected = %s" % S("tab_unselected"))
P("TabContainer/styles/tab_hovered = %s" % S("tab_hover"))
P("TabContainer/styles/tab_focus = %s" % S("focus"))
P("TabContainer/styles/panel = %s" % S("tab_panel"))
# Bars and sliders.
P("ProgressBar/colors/font_color = %s" % c(TEXT_BRIGHT))
P("ProgressBar/colors/font_outline_color = Color(0, 0, 0, 0.8)")
P("ProgressBar/constants/outline_size = 3")
P("ProgressBar/styles/background = %s" % S("bar_back"))
P("ProgressBar/styles/fill = %s" % S("bar_fill"))
P("HSlider/styles/slider = %s" % S("slider_track"))
P("HSlider/styles/grabber_area = %s" % S("slider_fill"))
P("HSlider/styles/grabber_area_highlight = %s" % S("slider_fill_hot"))
for sb in ("VScrollBar", "HScrollBar"):
    P("%s/styles/scroll = %s" % (sb, S("scroll_track")))
    P("%s/styles/scroll_focus = %s" % (sb, S("scroll_track")))
    P("%s/styles/grabber = %s" % (sb, S("scroll_grabber")))
    P("%s/styles/grabber_highlight = %s" % (sb, S("scroll_grabber_hot")))
    P("%s/styles/grabber_pressed = %s" % (sb, S("scroll_grabber_hot")))
# Spacing.
P("VBoxContainer/constants/separation = 8")
P("HBoxContainer/constants/separation = 8")
P("GridContainer/constants/h_separation = 12")
P("GridContainer/constants/v_separation = 6")

exts = [('FontVariation', 'res://themes/inter_body.tres', '1_body'), ('FontVariation', 'res://themes/inter_strong.tres', '2_strong'),
        ('FontVariation', 'res://themes/inter_bold.tres', '3_bold')]
out = ['[gd_resource type="Theme" load_steps=%d format=3]' % (len(subs) + len(exts) + 1), ""]
for t, p, i in exts:
    out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, i))
out.append("")
for s in subs:
    out.append(s)
    out.append("")
out.append("[resource]")
out.extend(props)
with open(os.path.join(ROOT, "themes", "contractor_ui.tres"), "w", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print("subs", len(subs), "props", len(props))
