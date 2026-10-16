import os
import math
import random
from PIL import Image, ImageDraw, ImageFilter

RAW_DIR = '/tmp/raw_frames'
MEDIA_DIR = '/opt/connecto-server/media/shop'
TARGET_SIZE = 640
CENTER = 320
INNER_RADIUS = 202
FEATHER = 6

def clean_volumetric_artwork(src_path, outer_r=295, bg_thresh=18, soft_range=15):
    src = Image.open(src_path).convert("RGBA")
    resized = src.resize((TARGET_SIZE, TARGET_SIZE), Image.Resampling.LANCZOS)
    pix = resized.load()
    
    for y in range(TARGET_SIZE):
        for x in range(TARGET_SIZE):
            dx = x - CENTER
            dy = y - CENTER
            dist = math.sqrt(dx*dx + dy*dy)
            
            r, g, b, a = pix[x, y]
            
            # 1. Inner avatar face opening:
            if dist < INNER_RADIUS - FEATHER:
                pix[x, y] = (0, 0, 0, 0)
                continue
            elif dist < INNER_RADIUS:
                edge_a = (dist - (INNER_RADIUS - FEATHER)) / float(FEATHER)
                pix[x, y] = (r, g, b, int(255 * edge_a))
                continue
                
            # 2. Outer boundary:
            if dist > outer_r:
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum <= bg_thresh:
                    pix[x, y] = (0, 0, 0, 0)
                elif lum <= bg_thresh + soft_range:
                    t = (lum - bg_thresh) / float(soft_range)
                    dist_fade = max(0.0, 1.0 - (dist - outer_r) / 28.0)
                    pix[x, y] = (r, g, b, int(255 * t * dist_fade))
                else:
                    dist_fade = max(0.0, 1.0 - (dist - outer_r) / 28.0)
                    pix[x, y] = (r, g, b, int(255 * dist_fade))
            else:
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum <= 5 and dist < INNER_RADIUS + 12:
                    pix[x, y] = (0, 0, 0, 0)
                else:
                    pix[x, y] = (r, g, b, 255)
                    
    return resized

def clear_inner_circle(frame):
    cutoff_r = INNER_RADIUS - FEATHER
    fpix = frame.load()
    for fy in range(CENTER - cutoff_r, CENTER + cutoff_r + 1):
        for fx in range(CENTER - cutoff_r, CENTER + cutoff_r + 1):
            dx = fx - CENTER
            dy = fy - CENTER
            if dx*dx + dy*dy < cutoff_r * cutoff_r:
                fpix[fx, fy] = (0, 0, 0, 0)
    return frame

def make_frames_sparks(base_im, n_frames=24):
    frames = []
    # 18 spark particles running around perimeter
    particles = []
    for i in range(18):
        particles.append({
            'base_angle': (i / 18.0) * 2 * math.pi,
            'speed': 1.0 if i % 2 == 0 else -0.85,
            'radius': 225 + (i * 3.7) % 55,
            'size': 2.5 + (i % 4),
            'color': (255, 60, 40) if i % 3 == 0 else ((255, 200, 50) if i % 3 == 1 else (255, 255, 220))
        })
        
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        # Subtle energetic breathe
        scale = 1.0 + 0.025 * math.sin(phase * 2)
        sw = int(TARGET_SIZE * scale)
        sh = int(TARGET_SIZE * scale)
        res = base_im.resize((sw, sh), Image.Resampling.BILINEAR)
        
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        frame.paste(res, ((TARGET_SIZE - sw) // 2, (TARGET_SIZE - sh) // 2), res)
        
        # Overlay layer for sparks & arcs
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # Electric lightning arcs between sparks
        arc_step = math.sin(phase * 3)
        if arc_step > 0.2:
            ang_start = phase * 2.0
            x1 = CENTER + math.cos(ang_start) * 245
            y1 = CENTER + math.sin(ang_start) * 245
            # Zig-zag arc
            xm = CENTER + math.cos(ang_start + 0.25) * (265 + 15 * math.cos(phase * 4))
            ym = CENTER + math.sin(ang_start + 0.25) * (265 + 15 * math.cos(phase * 4))
            x2 = CENTER + math.cos(ang_start + 0.5) * 250
            y2 = CENTER + math.sin(ang_start + 0.5) * 250
            draw.line([(x1, y1), (xm, ym), (x2, y2)], fill=(255, 240, 160, int(220 * arc_step)), width=3)
            
        # Draw running sparks with motion trails
        for p in particles:
            cur_ang = p['base_angle'] + p['speed'] * phase
            r = p['radius'] + 6 * math.sin(cur_ang * 3)
            cx = CENTER + math.cos(cur_ang) * r
            cy = CENTER + math.sin(cur_ang) * r
            
            # Tail
            tail_ang = cur_ang - p['speed'] * 0.15
            tx = CENTER + math.cos(tail_ang) * r
            ty = CENTER + math.sin(tail_ang) * r
            draw.line([(tx, ty), (cx, cy)], fill=(*p['color'][:3], 140), width=int(p['size']))
            
            # Head spark
            s = p['size']
            draw.ellipse((cx - s, cy - s, cx + s, cy + s), fill=(*p['color'][:3], 240))
            draw.ellipse((cx - s*0.5, cy - s*0.5, cx + s*0.5, cy + s*0.5), fill=(255, 255, 255, 255))
            
        # Anger cross shockwaves at top right (x~490, y~130)
        cross_x, cross_y = 485, 135
        pulse = 0.5 + 0.5 * math.sin(phase * 2)
        wave_r = int(10 + 35 * (t % 0.5) * 2)
        wave_a = int(180 * (1.0 - (t % 0.5) * 2))
        draw.ellipse((cross_x - wave_r, cross_y - wave_r, cross_x + wave_r, cross_y + wave_r),
                     outline=(255, 50, 50, wave_a), width=3)
                     
        frame = Image.alpha_composite(frame, overlay)
        frames.append(clear_inner_circle(frame))
    return frames

def make_frames_eyes(base_im, n_frames=24):
    frames = []
    # Distinct eyes around the perimeter to animate independently
    eyes_info = [
        {'cx': 320, 'cy': 85, 'rx': 24, 'ry': 12, 'type': 'blink', 'phase_off': 0.0},
        {'cx': 445, 'cy': 135, 'rx': 20, 'ry': 10, 'type': 'look_lr', 'phase_off': 0.5},
        {'cx': 195, 'cy': 135, 'rx': 20, 'ry': 10, 'type': 'look_diag', 'phase_off': 1.0},
        {'cx': 130, 'cy': 320, 'rx': 18, 'ry': 11, 'type': 'blink', 'phase_off': 1.5},
        {'cx': 510, 'cy': 320, 'rx': 18, 'ry': 11, 'type': 'look_lr', 'phase_off': 2.0},
        {'cx': 230, 'cy': 515, 'rx': 22, 'ry': 11, 'type': 'look_diag', 'phase_off': 2.5},
        {'cx': 410, 'cy': 515, 'rx': 22, 'ry': 11, 'type': 'blink', 'phase_off': 3.0},
        {'cx': 320, 'cy': 555, 'rx': 24, 'ry': 12, 'type': 'stare', 'phase_off': 0.0},
    ]
    
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        # Subtle eerie breathing
        scale = 1.0 + 0.015 * math.sin(phase)
        sw = int(TARGET_SIZE * scale)
        sh = int(TARGET_SIZE * scale)
        res = base_im.resize((sw, sh), Image.Resampling.BILINEAR)
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        frame.paste(res, ((TARGET_SIZE - sw) // 2, (TARGET_SIZE - sh) // 2), res)
        
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        for e in eyes_info:
            p_e = phase + e['phase_off']
            cx, cy = e['cx'], e['cy']
            rx, ry = e['rx'], e['ry']
            
            # Eyelid height calculation
            if e['type'] == 'blink':
                # Quick blink at a specific moment
                b_phase = math.sin(p_e)
                if b_phase > 0.8:
                    close_factor = (b_phase - 0.8) / 0.2
                    eff_ry = max(1, int(ry * (1.0 - close_factor)))
                else:
                    eff_ry = ry
            else:
                eff_ry = ry
                
            # Pupil offset
            if e['type'] == 'look_lr':
                p_dx = math.sin(p_e) * (rx * 0.45)
                p_dy = 0
            elif e['type'] == 'look_diag':
                p_dx = math.cos(p_e) * (rx * 0.35)
                p_dy = math.sin(p_e * 2) * (ry * 0.35)
            elif e['type'] == 'stare':
                # Small jitter
                p_dx = math.sin(p_e * 5) * 1.5
                p_dy = math.cos(p_e * 5) * 1.0
            else:
                p_dx = math.sin(p_e * 0.7) * (rx * 0.3)
                p_dy = 0
                
            # If blinking closed, draw closed eyelid line
            if eff_ry <= 2:
                draw.line([(cx - rx, cy), (cx + rx, cy)], fill=(20, 20, 25, 230), width=3)
            else:
                # Sclera glow
                draw.ellipse((cx - rx, cy - eff_ry, cx + rx, cy + eff_ry), fill=(240, 240, 245, 190))
                # Pupil
                pr = min(rx * 0.5, eff_ry * 0.8)
                px = cx + p_dx
                py = cy + p_dy
                draw.ellipse((px - pr, py - pr, px + pr, py + pr), fill=(10, 5, 20, 240))
                # Red demonic gleam in pupil
                gleam_r = pr * 0.35
                draw.ellipse((px - gleam_r, py - gleam_r, px + gleam_r, py + gleam_r), fill=(255, 30, 30, 220))
                
        frame = Image.alpha_composite(frame, overlay)
        frames.append(clear_inner_circle(frame))
    return frames

def make_frames_maw(base_im, n_frames=24):
    frames = []
    drips = [
        {'x': 255, 'top_y': 225, 'speed': 1.2, 'off': 0.0},
        {'x': 320, 'top_y': 218, 'speed': 1.0, 'off': 0.33},
        {'x': 385, 'top_y': 225, 'speed': 1.4, 'off': 0.66},
    ]
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        # Jaw clench & release: vertical stretch
        stretch = 1.0 + 0.035 * math.sin(phase)
        sh = int(TARGET_SIZE * stretch)
        res = base_im.resize((TARGET_SIZE, sh), Image.Resampling.BILINEAR)
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        frame.paste(res, (0, (TARGET_SIZE - sh) // 2), res)
        
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # Dripping saliva drops
        for d in drips:
            d_t = (t * d['speed'] + d['off']) % 1.0
            drop_y = d['top_y'] + int(d_t * 60)
            drop_len = int(3 + d_t * 8)
            alpha = int(220 * (1.0 - d_t * 0.6))
            draw.line([(d['x'], drop_y - drop_len), (d['x'], drop_y)], fill=(200, 230, 255, alpha), width=3)
            draw.ellipse((d['x'] - 3, drop_y - 2, d['x'] + 3, drop_y + 4), fill=(220, 240, 255, alpha))
            
        frame = Image.alpha_composite(frame, overlay)
        frames.append(clear_inner_circle(frame))
    return frames

def make_frames_eclipse(base_im, n_frames=24):
    frames = []
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        frame = base_im.copy()
        
        # Rotating solar flare plasma corona
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # 12 swirling solar flares
        for i in range(12):
            ang = phase + i * (2.0 * math.pi / 12.0)
            flare_len = 20 + 15 * math.sin(phase * 2 + i * 1.5)
            r_in = 228
            r_out = r_in + flare_len
            x1 = CENTER + math.cos(ang) * r_in
            y1 = CENTER + math.sin(ang) * r_in
            x2 = CENTER + math.cos(ang + 0.1) * r_out
            y2 = CENTER + math.sin(ang + 0.1) * r_out
            
            draw.line([(x1, y1), (x2, y2)], fill=(255, int(140 + 70 * math.sin(ang)), 20, 180), width=4)
            
        # Glowing corona ring
        corona = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        cd = ImageDraw.Draw(corona)
        cg_a = int(90 + 40 * math.sin(phase * 2))
        cd.ellipse((CENTER - 232, CENTER - 232, CENTER + 232, CENTER + 232), outline=(255, 160, 30, cg_a), width=12)
        corona = corona.filter(ImageFilter.GaussianBlur(8))
        
        frame = Image.alpha_composite(frame, corona)
        frame = Image.alpha_composite(frame, overlay)
        frames.append(clear_inner_circle(frame))
    return frames

def make_frames_wings(base_im, n_frames=24):
    frames = []
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        # Flapping horizontal cycle
        scale_x = 1.0 + 0.06 * math.sin(phase)
        sw = int(TARGET_SIZE * scale_x)
        res = base_im.resize((sw, TARGET_SIZE), Image.Resampling.BILINEAR)
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        frame.paste(res, ((TARGET_SIZE - sw) // 2, 0), res)
        
        # Floating cyan/lavender stardust
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        for p_i in range(14):
            p_ang = phase * 0.5 + p_i * (2.0 * math.pi / 14.0)
            r = 230 + (p_i * 7) % 60 + 10 * math.sin(phase + p_i)
            px = CENTER + math.cos(p_ang) * r
            py = CENTER + math.sin(p_ang) * r
            p_a = int(220 * (0.5 + 0.5 * math.sin(phase * 2 + p_i)))
            col = (130, 240, 255, p_a) if p_i % 2 == 0 else (220, 160, 255, p_a)
            draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill=col)
            
        frame = Image.alpha_composite(frame, overlay)
        frames.append(clear_inner_circle(frame))
    return frames

def make_frames_generic(base_im, n_frames=24, color=(255, 230, 150)):
    frames = []
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        dy = int(math.sin(phase) * 4)
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        frame.paste(base_im, (0, dy), base_im)
        
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # 12 orbiting sparkles
        for p_i in range(12):
            p_ang = phase + p_i * (2.0 * math.pi / 12.0)
            r = 235 + (p_i * 6) % 55
            px = CENTER + math.cos(p_ang) * r
            py = CENTER + math.sin(p_ang) * r
            p_a = int(210 * (0.5 + 0.5 * math.sin(phase * 2 + p_i)))
            draw.ellipse((px - 2.5, py - 2.5, px + 2.5, py + 2.5), fill=(*color[:3], p_a))
            
        frame = Image.alpha_composite(frame, overlay)
        frames.append(clear_inner_circle(frame))
    return frames

def main():
    artworks_map = [
        ("fr_dc_sparks", "anime_anger_shockwave_frame_1791911257022.jpg", "sparks", 295),
        ("fr_dc_horror_eyes", "frame_manga_eyes_1791911194447.jpg", "eyes", 295),
        ("fr_dc_horror_maw", "frame_monster_teeth_1791911177955.jpg", "maw", 295),
        ("fr_dc_solar_eclipse", "frame_solar_eclipse_1791911210643.jpg", "eclipse", 295),
        ("fr_dc_dark_roses", "frame_fairy_moth_wings_1791911226936.jpg", "wings", 300),
        ("fr_dc_fox_ears", "frame_cute_cat_1791911213719.jpg", "cat", 310),
        ("fr_dc_white_roses", "frame_silver_roses_1791911233371.jpg", "roses", 298),
        ("fr_dc_wolf_moon", "crescent_moon_celestial_frame_1791911178814.jpg", "moon", 300),
        ("fr_dc_hades", "ghoul_claws_shadow_frame_1791911202496.jpg", "maw", 295),
        ("fr_dc_pumpkins", "autumn_leaves_sleeping_cat_frame_v2_1791911239134.jpg", "leaves", 300),
        ("fr_dc_snow_leopard", "frame_raccoon_1791911179002.jpg", "cat", 305),
        ("fr_dc_witch_hat", "frame_spooky_ghoul_1791911242931.jpg", "eyes", 300),
    ]

    for item_id, file_name, anim, outer_r in artworks_map:
        raw_path = os.path.join(RAW_DIR, file_name)
        if not os.path.exists(raw_path):
            print(f"ERROR: {raw_path} not found!")
            continue
            
        print(f"Generating detailed 2D animation for {item_id} ({anim})...")
        matted = clean_volumetric_artwork(raw_path, outer_r=outer_r)
        
        if anim == "sparks":
            frames = make_frames_sparks(matted)
        elif anim == "eyes":
            frames = make_frames_eyes(matted)
        elif anim == "maw":
            frames = make_frames_maw(matted)
        elif anim == "eclipse":
            frames = make_frames_eclipse(matted)
        elif anim == "wings":
            frames = make_frames_wings(matted)
        elif anim == "cat":
            frames = make_frames_generic(matted, color=(255, 190, 220))
        elif anim == "roses":
            frames = make_frames_generic(matted, color=(220, 235, 255))
        elif anim == "moon":
            frames = make_frames_generic(matted, color=(255, 250, 190))
        elif anim == "leaves":
            frames = make_frames_generic(matted, color=(255, 140, 40))
        else:
            frames = make_frames_generic(matted)
            
        webp_path = os.path.join(MEDIA_DIR, f"{item_id}.webp")
        frames[0].save(webp_path, format="WEBP", save_all=True, append_images=frames[1:], duration=60, loop=0, quality=92)
        
        png_path = os.path.join(MEDIA_DIR, f"{item_id}.png")
        frames[0].save(png_path, format="PNG")
        print(f"  -> Saved {item_id}.webp and {item_id}.png")

    print("ALL 12 DETAILED ANIMATIONS GENERATED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
