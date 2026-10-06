#version 300 es
// Blackout screen shader, applied by DimOverlay once the absence fade is
// complete. Hyprland runs screen shaders after colour management, on the
// output signal itself, so 0 here is 0 nits. An SDR black surface is not:
// in HDR (cm = hdredid) it maps to sdr_min_luminance (0.2 nits), a lit panel.
// The software cursor is drawn before this pass, so it goes dark too.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
}
