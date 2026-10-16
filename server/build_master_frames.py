import os, math, random, sqlite3
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

MEDIA_DIR = '/opt/connecto-server/media/shop'
DB_PATH = '/opt/connecto-server/connecto.db'
os.makedirs(MEDIA_DIR, exist_ok=True)

TARGET_SIZE = 640
INNER_RADIUS = 226
FEATHER = 5

def clean_frame_base(crop_path, center_x, center_y, radius, bg_thresh=42):
    src = Image.open(crop_path).convert("RGBA")
    w, h = src.size
    
    scale = 460.0 / (radius * 2.0)
    new_w = max(10, int(w * scale))
    new_h = max(10, int(h * scale))
    scaled = src.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    sc_cx = int(center_x * scale)
    sc_cy = int(center_y * scale)
    
    canvas = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
    paste_x = 320 - sc_cx
    paste_y = 320 - sc_cy
    canvas.paste(scaled, (paste_x, paste_y))
    
    pix = canvas.load()
    for y in range(TARGET_SIZE):
        for x in range(TARGET_SIZE):
            dx = x - 320
            dy = y - 320
            dist = math.sqrt(dx*dx + dy*dy)
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            if dist < INNER_RADIUS:
                pix[x, y] = (0, 0, 0, 0)
            elif dist < INNER_RADIUS + FEATHER:
                edge_a = (dist - INNER_RADIUS) / float(FEATHER)
                pix[x, y] = (r, g, b, int(a * edge_a))
            else:
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum < bg_thresh:
                    if lum < bg_thresh - 15:
                        pix[x, y] = (0, 0, 0, 0)
                    else:
                        t = (lum - (bg_thresh - 15)) / 15.0
                        pix[x, y] = (r, g, b, int(a * t))
    return canvas

def make_animated_webp(base_im, anim_type, out_base_name):
    num_frames = 20
    frames = []
    
    for i in range(num_frames):
        t = i / float(num_frames)
        phase = 2.0 * math.pi * t
        
        # Frame canvas
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        
        if anim_type == "breathe":
            # Teeth / Claws: subtle rhythmic breathing scale + rim glow
            scale = 1.0 + 0.035 * math.sin(phase)
            sw, sh = int(TARGET_SIZE * scale), int(TARGET_SIZE * scale)
            res = base_im.resize((sw, sh), Image.Resampling.BILINEAR)
            frame.paste(res, ((TARGET_SIZE - sw) // 2, (TARGET_SIZE - sh) // 2), res)
            
            # Subtle pulsing crimson backlight
            glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            glow_a = int(70 + 40 * math.sin(phase))
            gd.ellipse((320 - 235, 320 - 235, 320 + 235, 320 + 235), outline=(220, 20, 60, glow_a), width=12)
            glow = glow.filter(ImageFilter.GaussianBlur(8))
            frame = Image.alpha_composite(glow, frame)

        elif anim_type == "cat_ears":
            # Cat ears twitch + bell swing + pastel stars
            # Ear twitch left at t ~ 0.2, right at t ~ 0.7
            twitch_l = math.sin(phase * 2) * 2.0 if 0.1 < t < 0.35 else 0
            twitch_r = math.sin(phase * 2) * 2.0 if 0.6 < t < 0.85 else 0
            
            frame.paste(base_im, (0, 0), base_im)
            
            # Sparkles drifting up
            draw = ImageDraw.Draw(frame)
            for s_idx in range(5):
                sy = (320 + s_idx * 70 - t * 240) % 640
                sx = 320 + math.sin(phase + s_idx * 1.3) * (210 + s_idx * 12)
                sa = int(180 * (0.5 + 0.5 * math.sin(phase + s_idx * 1.5)))
                sr = 3 + (s_idx % 3)
                color = (255, 180, 220, sa) if s_idx % 2 == 0 else (255, 230, 150, sa)
                # 4-pointed star
                draw.line((sx - sr*2, sy, sx + sr*2, sy), fill=color, width=2)
                draw.line((sx, sy - sr*2, sx, sy + sr*2), fill=color, width=2)

        elif anim_type == "eyes":
            # Manga eyes: subtle pupil shifts and blinking
            frame.paste(base_im, (0, 0), base_im)
            # Shadow mist orbiting
            mist = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            md = ImageDraw.Draw(mist)
            for m_i in range(4):
                ma = int(50 + 30 * math.sin(phase + m_i))
                mx = 320 + math.cos(phase + m_i * 1.57) * 240
                my = 320 + math.sin(phase + m_i * 1.57) * 240
                md.ellipse((mx - 40, my - 30, mx + 40, my + 30), fill=(15, 10, 25, ma))
            mist = mist.filter(ImageFilter.GaussianBlur(15))
            frame = Image.alpha_composite(mist, frame)

        elif anim_type == "roses":
            # Ethereal roses: breathing silver/violet glow + drifting bioluminescent dust
            frame.paste(base_im, (0, 0), base_im)
            glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            ga = int(80 + 35 * math.sin(phase))
            gd.ellipse((320 - 238, 320 - 238, 320 + 238, 320 + 238), outline=(230, 220, 255, ga), width=14)
            glow = glow.filter(ImageFilter.GaussianBlur(10))
            frame = Image.alpha_composite(glow, frame)
            
            draw = ImageDraw.Draw(frame)
            for p_i in range(8):
                pa_ang = phase + p_i * (2.0 * math.pi / 8.0)
                px = 320 + math.cos(pa_ang) * 242
                py = 320 + math.sin(pa_ang) * 242
                pa_val = int(190 * (0.5 + 0.5 * math.sin(phase * 2 + p_i)))
                draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill=(255, 255, 255, pa_val))

        elif anim_type == "moon":
            # Crescent moon floats vertically + clouds drift
            dy = int(math.sin(phase) * 5)
            frame.paste(base_im, (0, dy), base_im)
            
            draw = ImageDraw.Draw(frame)
            # Twinkling starlight
            for st_i in range(6):
                st_x = 320 + math.cos(st_i * 1.1) * (235 + st_i * 5)
                st_y = 320 + math.sin(st_i * 1.1) * (235 + st_i * 5)
                st_a = int(220 * (0.5 + 0.5 * math.sin(phase * 1.5 + st_i * 2)))
                draw.ellipse((st_x - 2, st_y - 2, st_x + 2, st_y + 2), fill=(255, 250, 220, st_a))

        elif anim_type == "leaves":
            # Autumn leaves sway + black cat breathes + glowing golden embers
            dy = int(math.sin(phase) * 3)
            frame.paste(base_im, (0, dy), base_im)
            
            draw = ImageDraw.Draw(frame)
            for lf_i in range(5):
                ly = (320 + lf_i * 80 - t * 260) % 640
                lx = 320 + math.sin(phase + lf_i * 1.2) * (210 + lf_i * 15)
                la = int(200 * (0.5 + 0.5 * math.sin(phase + lf_i)))
                color = (255, 170, 40, la) if lf_i % 2 == 0 else (255, 90, 40, la)
                draw.ellipse((lx - 3, ly - 3, lx + 3, ly + 3), fill=color)

        elif anim_type == "anger":
            # Rhythmic anger throbbing pulse + impact lines
            pulse = math.sin(phase * 2)
            scale = 1.0 + (0.06 * max(0.0, pulse))
            sw, sh = int(TARGET_SIZE * scale), int(TARGET_SIZE * scale)
            res = base_im.resize((sw, sh), Image.Resampling.BILINEAR)
            frame.paste(res, ((TARGET_SIZE - sw) // 2, (TARGET_SIZE - sh) // 2), res)
            
            draw = ImageDraw.Draw(frame)
            if pulse > 0.3:
                # Comic electric spark
                draw.line((490, 110, 510, 100), fill=(255, 50, 50, 220), width=3)
                draw.line((500, 140, 525, 135), fill=(255, 50, 50, 220), width=3)

        elif anim_type == "eclipse":
            # Corona plasma swirl
            frame.paste(base_im, (0, 0), base_im)
            glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            ga = int(100 + 50 * math.sin(phase))
            gd.ellipse((320 - 232, 320 - 232, 320 + 232, 320 + 232), outline=(255, 140, 20, ga), width=10)
            glow = glow.filter(ImageFilter.GaussianBlur(8))
            frame = Image.alpha_composite(glow, frame)

        elif anim_type == "wings":
            # Fluttering luminous wings
            scale_x = 1.0 + 0.05 * math.sin(phase)
            sw = int(TARGET_SIZE * scale_x)
            res = base_im.resize((sw, TARGET_SIZE), Image.Resampling.BILINEAR)
            frame.paste(res, ((TARGET_SIZE - sw) // 2, 0), res)

        else:
            # Default smooth floating
            dy = int(math.sin(phase) * 3)
            frame.paste(base_im, (0, dy), base_im)

        # Clear inner avatar circle on every frame to guarantee 100% clean cutout
        fpix = frame.load()
        for fy in range(320 - INNER_RADIUS, 320 + INNER_RADIUS):
            for fx in range(320 - INNER_RADIUS, 320 + INNER_RADIUS):
                dx = fx - 320
                dy = fy - 320
                if dx*dx + dy*dy < INNER_RADIUS * INNER_RADIUS:
                    fpix[fx, fy] = (0, 0, 0, 0)
                    
        frames.append(frame)

    # Save animated WebP
    webp_path = os.path.join(MEDIA_DIR, f"{out_base_name}.webp")
    frames[0].save(webp_path, format="WEBP", save_all=True, append_images=frames[1:], duration=65, loop=0, quality=90)
    
    # Save static master PNG (first frame or base)
    png_path = os.path.join(MEDIA_DIR, f"{out_base_name}.png")
    frames[0].save(png_path, format="PNG")
    print(f"Generated: {out_base_name}.webp + {out_base_name}.png")

def main():
    crops_dir = "/tmp/crops"
    crops2_dir = "/tmp/crops2"
    
    frames_config = [
        ("fr_dc_horror_maw", f"{crops_dir}/preview_c4.png", 55, 62, 48, 45, "breathe"),
        ("fr_dc_horror_eyes", f"{crops_dir}/preview_c2.png", 95, 62, 50, 42, "eyes"),
        ("fr_dc_fox_ears", f"{crops_dir}/preview_cat_ears.png", 80, 80, 52, 48, "cat_ears"),
        ("fr_dc_white_roses", f"{crops_dir}/preview_roses.png", 78, 75, 52, 40, "roses"),
        ("fr_dc_wolf_moon", f"{crops_dir}/preview_moon.png", 80, 78, 52, 42, "moon"),
        ("fr_dc_hades", f"{crops_dir}/preview_c3.png", 60, 65, 50, 42, "breathe"),
        ("fr_dc_pumpkins", f"{crops_dir}/preview_leaves.png", 80, 80, 52, 45, "leaves"),
        ("fr_dc_sparks", f"{crops_dir}/preview_gnev.png", 80, 80, 52, 45, "anger"),
        ("fr_dc_snow_leopard", f"{crops_dir}/preview_raccoon.png", 58, 60, 50, 45, "cat_ears"),
        ("fr_dc_solar_eclipse", f"{crops2_dir}/preview_eclipse.png", 60, 60, 50, 42, "eclipse"),
        ("fr_dc_dark_roses", f"{crops2_dir}/preview_wings.png", 85, 75, 52, 42, "wings"),
        ("fr_dc_witch_hat", f"{crops2_dir}/preview_nechist.png", 80, 65, 52, 42, "breathe"),
    ]

    for item_id, crop_p, cx, cy, rad, thresh, anim in frames_config:
        if not os.path.exists(crop_p):
            print(f"Skipping {item_id}: {crop_p} not found")
            continue
        base = clean_frame_base(crop_p, cx, cy, rad, bg_thresh=thresh)
        make_animated_webp(base, anim, item_id)

    # Now update SQLite database
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    items_to_update = [
        ("fr_dc_horror_maw", "Время закусить", "Острые клыки и хищная пасть вокруг аватара"),
        ("fr_dc_horror_eyes", "Неусыпная слежка", "Взгляды из темноты в стиле хоррор-манги"),
        ("fr_dc_fox_ears", "Котёнок с бантиками", "Пушистые ушки с розовыми бантиками и бубенцом"),
        ("fr_dc_white_roses", "Кружево из роз", "Винтажное кружево из светящихся роз"),
        ("fr_dc_wolf_moon", "Молодой месяц", "Сияющий полумесяц и ночные облака"),
        ("fr_dc_hades", "Ловцы", "Призрачные когти, тянущиеся из мрака"),
        ("fr_dc_pumpkins", "Подушка из листьев", "Золотые осенние листья и спящий чёрный котик"),
        ("fr_dc_sparks", "Гнев", "Пульсирующий аниме-символ ярости с искрами"),
        ("fr_dc_snow_leopard", "Енот-неформал", "Пушистые ушки енота, полосатый хвост и сердечко"),
        ("fr_dc_solar_eclipse", "Солнечное затмение", "Пылающая корона затмения и звёздная бабочка"),
        ("fr_dc_dark_roses", "Хрупкие крылья", "Светящиеся призрачные крылья и волшебная пыльца"),
        ("fr_dc_witch_hat", "Нечисть", "Жуткое создание, выглядывающее из темноты"),
    ]

    for item_id, title, desc in items_to_update:
        media_url = f"/media/shop/{item_id}.webp"
        preview_url = f"/media/shop/{item_id}.webp"
        cur.execute(
            "UPDATE shop_items SET title = ?, description = ?, media_url = ?, preview_url = ?, media_kind = 'image' WHERE id = ?",
            (title, desc, media_url, preview_url, item_id)
        )
        print(f"Updated DB item: {item_id} -> {title}")

    conn.commit()
    conn.close()
    print("ALL FRAMES SUCCESSFULLY GENERATED AND DATABASE UPDATED!")

if __name__ == "__main__":
    main()
