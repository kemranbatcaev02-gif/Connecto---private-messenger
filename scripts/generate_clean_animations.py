import os
import math
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
            
            # Inner circle for avatar
            if dist < INNER_RADIUS - FEATHER:
                pix[x, y] = (0, 0, 0, 0)
                continue
            elif dist < INNER_RADIUS:
                edge_a = (dist - (INNER_RADIUS - FEATHER)) / float(FEATHER)
                pix[x, y] = (r, g, b, int(255 * edge_a))
                continue
                
            # Outer boundary
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

def make_frames_sparks(base_im, n_frames=20):
    frames = []
    # Particles running around the perimeter
    particles = []
    for i in range(16):
        particles.append({
            'base_angle': (i / 16.0) * 2 * math.pi,
            'speed': 1.0 if i % 2 == 0 else -0.75,
            'radius': 230 + (i * 5) % 45,
            'size': 3.0 + (i % 3),
            'color': (255, 60, 40) if i % 3 == 0 else ((255, 210, 50) if i % 3 == 1 else (255, 255, 230))
        })
        
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        # Base image is 100% STATIC - NO SCALING, NO JITTER!
        frame = base_im.copy()
        
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # Lightning arc between particles
        if math.sin(phase * 3) > 0.3:
            ang_start = phase * 2.0
            x1 = CENTER + math.cos(ang_start) * 245
            y1 = CENTER + math.sin(ang_start) * 245
            xm = CENTER + math.cos(ang_start + 0.3) * 270
            ym = CENTER + math.sin(ang_start + 0.3) * 270
            x2 = CENTER + math.cos(ang_start + 0.6) * 250
            y2 = CENTER + math.sin(ang_start + 0.6) * 250
            draw.line([(x1, y1), (xm, ym), (x2, y2)], fill=(255, 240, 160, 200), width=3)
            
        # Draw moving sparks with trails
        for p in particles:
            cur_ang = p['base_angle'] + p['speed'] * phase
            r = p['radius'] + 4 * math.sin(cur_ang * 2)
            cx = CENTER + math.cos(cur_ang) * r
            cy = CENTER + math.sin(cur_ang) * r
            
            tail_ang = cur_ang - p['speed'] * 0.18
            tx = CENTER + math.cos(tail_ang) * r
            ty = CENTER + math.sin(tail_ang) * r
            draw.line([(tx, ty), (cx, cy)], fill=(*p['color'][:3], 150), width=int(p['size']))
            
            s = p['size']
            draw.ellipse((cx - s, cy - s, cx + s, cy + s), fill=(*p['color'][:3], 240))
            draw.ellipse((cx - s*0.5, cy - s*0.5, cx + s*0.5, cy + s*0.5), fill=(255, 255, 255, 255))
            
        # Shockwaves from anger mark (top-right ~485, 135)
        cross_x, cross_y = 485, 135
        wave_t = (t * 2) % 1.0
        wave_r = int(8 + 32 * wave_t)
        wave_a = int(180 * (1.0 - wave_t))
        draw.ellipse((cross_x - wave_r, cross_y - wave_r, cross_x + wave_r, cross_y + wave_r),
                     outline=(255, 60, 60, wave_a), width=3)
                     
        frame = Image.alpha_composite(frame, overlay)
        frames.append(frame)
    return frames

def make_frames_eyes(base_im, n_frames=20):
    frames = []
    eyes_info = [
        {'cx': 320, 'cy': 90, 'rx': 22, 'ry': 12, 'type': 'blink', 'off': 0.0},
        {'cx': 445, 'cy': 140, 'rx': 20, 'ry': 10, 'type': 'look_lr', 'off': 0.5},
        {'cx': 195, 'cy': 140, 'rx': 20, 'ry': 10, 'type': 'look_diag', 'off': 1.0},
        {'cx': 130, 'cy': 320, 'rx': 18, 'ry': 11, 'type': 'blink', 'off': 1.5},
        {'cx': 510, 'cy': 320, 'rx': 18, 'ry': 11, 'type': 'look_lr', 'off': 2.0},
        {'cx': 230, 'cy': 510, 'rx': 22, 'ry': 11, 'type': 'look_diag', 'off': 2.5},
        {'cx': 410, 'cy': 510, 'rx': 22, 'ry': 11, 'type': 'blink', 'off': 3.0},
        {'cx': 320, 'cy': 550, 'rx': 24, 'ry': 12, 'type': 'stare', 'off': 0.0},
    ]
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        frame = base_im.copy()
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        for e in eyes_info:
            p_e = phase + e['off']
            cx, cy = e['cx'], e['cy']
            rx, ry = e['rx'], e['ry']
            
            # Blinking
            if e['type'] == 'blink':
                b_phase = math.sin(p_e)
                if b_phase > 0.8:
                    close_f = (b_phase - 0.8) / 0.2
                    eff_ry = max(1, int(ry * (1.0 - close_f)))
                else:
                    eff_ry = ry
            else:
                eff_ry = ry
                
            # Pupil movement
            if e['type'] == 'look_lr':
                p_dx = math.sin(p_e) * (rx * 0.4)
                p_dy = 0
            elif e['type'] == 'look_diag':
                p_dx = math.cos(p_e) * (rx * 0.3)
                p_dy = math.sin(p_e * 2) * (ry * 0.3)
            elif e['type'] == 'stare':
                p_dx = math.sin(p_e * 4) * 1.5
                p_dy = math.cos(p_e * 4) * 1.0
            else:
                p_dx = math.sin(p_e * 0.8) * (rx * 0.25)
                p_dy = 0
                
            if eff_ry <= 2:
                draw.line([(cx - rx, cy), (cx + rx, cy)], fill=(20, 20, 25, 230), width=3)
            else:
                draw.ellipse((cx - rx, cy - eff_ry, cx + rx, cy + eff_ry), fill=(240, 240, 245, 180))
                pr = min(rx * 0.45, eff_ry * 0.75)
                px = cx + p_dx
                py = cy + p_dy
                draw.ellipse((px - pr, py - pr, px + pr, py + pr), fill=(10, 5, 20, 240))
                gleam_r = pr * 0.35
                draw.ellipse((px - gleam_r, py - gleam_r, px + gleam_r, py + gleam_r), fill=(255, 30, 30, 220))
                
        frame = Image.alpha_composite(frame, overlay)
        frames.append(frame)
    return frames

def make_frames_maw(base_im, n_frames=20):
    frames = []
    drips = [
        {'x': 255, 'top_y': 230, 'speed': 1.0, 'off': 0.0},
        {'x': 320, 'top_y': 222, 'speed': 1.0, 'off': 0.33},
        {'x': 385, 'top_y': 230, 'speed': 1.0, 'off': 0.66},
    ]
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        
        frame = base_im.copy()
        
        # Demonic pulse in center
        glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        ga = int(45 + 25 * math.sin(phase))
        gd.ellipse((CENTER - 200, CENTER - 200, CENTER + 200, CENTER + 200), fill=(200, 20, 40, ga))
        glow = glow.filter(ImageFilter.GaussianBlur(14))
        frame = Image.alpha_composite(frame, glow)
        
        # Dripping saliva
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        for d in drips:
            d_t = (t * d['speed'] + d['off']) % 1.0
            drop_y = d['top_y'] + int(d_t * 55)
            drop_len = int(3 + d_t * 7)
            alpha = int(220 * (1.0 - d_t * 0.6))
            draw.line([(d['x'], drop_y - drop_len), (d['x'], drop_y)], fill=(200, 230, 255, alpha), width=3)
            draw.ellipse((d['x'] - 3, drop_y - 2, d['x'] + 3, drop_y + 4), fill=(220, 240, 255, alpha))
            
        frame = Image.alpha_composite(frame, overlay)
        frames.append(frame)
    return frames

def make_frames_eclipse(base_im, n_frames=20):
    frames = []
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        frame = base_im.copy()
        
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # 12 swirling solar flares
        for i in range(12):
            ang = phase + i * (2.0 * math.pi / 12.0)
            flare_len = 18 + 14 * math.sin(phase * 2 + i * 1.5)
            r_in = 230
            r_out = r_in + flare_len
            x1 = CENTER + math.cos(ang) * r_in
            y1 = CENTER + math.sin(ang) * r_in
            x2 = CENTER + math.cos(ang + 0.1) * r_out
            y2 = CENTER + math.sin(ang + 0.1) * r_out
            draw.line([(x1, y1), (x2, y2)], fill=(255, int(150 + 60 * math.sin(ang)), 20, 180), width=4)
            
        # Glowing corona
        corona = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        cd = ImageDraw.Draw(corona)
        cg_a = int(85 + 35 * math.sin(phase * 2))
        cd.ellipse((CENTER - 232, CENTER - 232, CENTER + 232, CENTER + 232), outline=(255, 160, 30, cg_a), width=10)
        corona = corona.filter(ImageFilter.GaussianBlur(8))
        
        frame = Image.alpha_composite(frame, corona)
        frame = Image.alpha_composite(frame, overlay)
        frames.append(frame)
    return frames

def make_frames_sparkles(base_im, color=(255, 230, 160), n_frames=20):
    frames = []
    for f in range(n_frames):
        t = f / float(n_frames)
        phase = t * 2.0 * math.pi
        frame = base_im.copy()
        
        overlay = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        for p_i in range(12):
            p_ang = phase + p_i * (2.0 * math.pi / 12.0)
            r = 235 + (p_i * 6) % 50
            px = CENTER + math.cos(p_ang) * r
            py = CENTER + math.sin(p_ang) * r
            p_a = int(210 * (0.5 + 0.5 * math.sin(phase * 2 + p_i)))
            draw.ellipse((px - 2.5, py - 2.5, px + 2.5, py + 2.5), fill=(*color[:3], p_a))
            # 4-point star gleam
            if p_a > 150:
                gl = 4
                draw.line([(px - gl, py), (px + gl, py)], fill=(255, 255, 255, p_a), width=1)
                draw.line([(px, py - gl), (px, py + gl)], fill=(255, 255, 255, p_a), width=1)
                
        frame = Image.alpha_composite(frame, overlay)
        frames.append(frame)
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
            continue
            
        print(f"Generating clean static & animated frame for {item_id} ({anim})...")
        matted = clean_volumetric_artwork(raw_path, outer_r=outer_r)
        
        # Save static PNG - pristine reference
        png_path = os.path.join(MEDIA_DIR, f"{item_id}.png")
        matted.save(png_path, format="PNG")
        
        if anim == "sparks":
            frames = make_frames_sparks(matted)
        elif anim == "eyes":
            frames = make_frames_eyes(matted)
        elif anim == "maw":
            frames = make_frames_maw(matted)
        elif anim == "eclipse":
            frames = make_frames_eclipse(matted)
        elif anim == "cat":
            frames = make_frames_sparkles(matted, color=(255, 190, 225))
        elif anim == "roses":
            frames = make_frames_sparkles(matted, color=(220, 235, 255))
        elif anim == "moon":
            frames = make_frames_sparkles(matted, color=(255, 245, 180))
        elif anim == "leaves":
            frames = make_frames_sparkles(matted, color=(255, 150, 40))
        elif anim == "wings":
            frames = make_frames_sparkles(matted, color=(140, 230, 255))
        else:
            frames = make_frames_sparkles(matted)
            
        webp_path = os.path.join(MEDIA_DIR, f"{item_id}.webp")
        frames[0].save(webp_path, format="WEBP", save_all=True, append_images=frames[1:], duration=65, loop=0, quality=90)
        print(f"  -> SUCCESS: {item_id}.webp and {item_id}.png")

    print("ALL 12 CLEAN ROCK-SOLID ANIMATIONS UPDATED!")

if __name__ == "__main__":
    main()
