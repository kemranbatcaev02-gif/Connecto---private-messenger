import os, math, sqlite3
from PIL import Image, ImageDraw, ImageFilter

RAW_DIR = '/tmp/raw_frames'
MEDIA_DIR = '/opt/connecto-server/media/shop'
DB_PATH = '/opt/connecto-server/connecto.db'
os.makedirs(MEDIA_DIR, exist_ok=True)

TARGET_SIZE = 640
INNER_RADIUS = 224
FEATHER = 5

def clean_and_matte_artwork(src_path, bg_thresh=25, soft_range=20):
    src = Image.open(src_path).convert("RGBA")
    w, h = src.size
    
    # Resize to TARGET_SIZE x TARGET_SIZE
    resized = src.resize((TARGET_SIZE, TARGET_SIZE), Image.Resampling.LANCZOS)
    pix = resized.load()
    
    # Process each pixel for transparent avatar hole + black background removal
    for y in range(TARGET_SIZE):
        for x in range(TARGET_SIZE):
            dx = x - 320
            dy = y - 320
            dist = math.sqrt(dx*dx + dy*dy)
            
            r, g, b, a = pix[x, y]
            
            # 1. Clear inner circular avatar cutout
            if dist < INNER_RADIUS:
                pix[x, y] = (0, 0, 0, 0)
                continue
            elif dist < INNER_RADIUS + FEATHER:
                edge_a = (dist - INNER_RADIUS) / float(FEATHER)
                # Also apply luminance to the inner edge
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum < bg_thresh:
                    pix[x, y] = (0, 0, 0, 0)
                else:
                    pix[x, y] = (r, g, b, int(255 * edge_a))
                continue
            
            # 2. Outer area: Remove solid black background
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum < bg_thresh:
                pix[x, y] = (0, 0, 0, 0)
            elif lum < bg_thresh + soft_range:
                t = (lum - bg_thresh) / float(soft_range)
                pix[x, y] = (r, g, b, int(255 * t))
            else:
                pix[x, y] = (r, g, b, 255)
                
    return resized

def generate_animation_frames(base_im, anim_type):
    num_frames = 20
    frames = []
    
    for i in range(num_frames):
        t = i / float(num_frames)
        phase = 2.0 * math.pi * t
        
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        
        if anim_type == "breathe":
            # Teeth / Claws / Ghoul: organic breathing scale
            scale = 1.0 + 0.032 * math.sin(phase)
            sw, sh = int(TARGET_SIZE * scale), int(TARGET_SIZE * scale)
            res = base_im.resize((sw, sh), Image.Resampling.BILINEAR)
            frame.paste(res, ((TARGET_SIZE - sw) // 2, (TARGET_SIZE - sh) // 2), res)
            
            # Subtle crimson backlight pulse
            glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            glow_a = int(60 + 35 * math.sin(phase))
            gd.ellipse((320 - 232, 320 - 232, 320 + 232, 320 + 232), outline=(230, 20, 50, glow_a), width=12)
            glow = glow.filter(ImageFilter.GaussianBlur(8))
            frame = Image.alpha_composite(glow, frame)

        elif anim_type == "cat_ears":
            # Cat ears + bell swing + pastel stars
            frame.paste(base_im, (0, 0), base_im)
            
            # Floating pastel stars
            draw = ImageDraw.Draw(frame)
            for s_idx in range(6):
                sy = (320 + s_idx * 65 - t * 240) % 640
                sx = 320 + math.sin(phase + s_idx * 1.3) * (212 + s_idx * 12)
                sa = int(200 * (0.5 + 0.5 * math.sin(phase + s_idx * 1.5)))
                sr = 3 + (s_idx % 3)
                color = (255, 185, 225, sa) if s_idx % 2 == 0 else (255, 235, 160, sa)
                draw.line((sx - sr*2, sy, sx + sr*2, sy), fill=color, width=2)
                draw.line((sx, sy - sr*2, sx, sy + sr*2), fill=color, width=2)

        elif anim_type == "eyes":
            # Manga eyes: swirling shadow mist + subtle pupil shifting
            frame.paste(base_im, (0, 0), base_im)
            mist = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            md = ImageDraw.Draw(mist)
            for m_i in range(4):
                ma = int(45 + 25 * math.sin(phase + m_i))
                mx = 320 + math.cos(phase + m_i * 1.57) * 240
                my = 320 + math.sin(phase + m_i * 1.57) * 240
                md.ellipse((mx - 35, my - 25, mx + 35, my + 25), fill=(20, 10, 30, ma))
            mist = mist.filter(ImageFilter.GaussianBlur(14))
            frame = Image.alpha_composite(mist, frame)

        elif anim_type == "roses":
            # Ethereal roses: silver breathing aura + drifting bioluminescent dust
            frame.paste(base_im, (0, 0), base_im)
            glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            ga = int(75 + 35 * math.sin(phase))
            gd.ellipse((320 - 235, 320 - 235, 320 + 235, 320 + 235), outline=(225, 220, 255, ga), width=14)
            glow = glow.filter(ImageFilter.GaussianBlur(9))
            frame = Image.alpha_composite(glow, frame)
            
            draw = ImageDraw.Draw(frame)
            for p_i in range(8):
                pa_ang = phase + p_i * (2.0 * math.pi / 8.0)
                px = 320 + math.cos(pa_ang) * 242
                py = 320 + math.sin(pa_ang) * 242
                pa_val = int(210 * (0.5 + 0.5 * math.sin(phase * 2 + p_i)))
                draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill=(255, 255, 255, pa_val))

        elif anim_type == "moon":
            # Crescent moon gentle vertical float + twinkling stars
            dy = int(math.sin(phase) * 5)
            frame.paste(base_im, (0, dy), base_im)
            
            draw = ImageDraw.Draw(frame)
            for st_i in range(6):
                st_x = 320 + math.cos(st_i * 1.1) * (236 + st_i * 4)
                st_y = 320 + math.sin(st_i * 1.1) * (236 + st_i * 4)
                st_a = int(220 * (0.5 + 0.5 * math.sin(phase * 1.5 + st_i * 2)))
                draw.ellipse((st_x - 2, st_y - 2, st_x + 2, st_y + 2), fill=(255, 250, 220, st_a))

        elif anim_type == "leaves":
            # Autumn leaves sway + black cat breathes + glowing golden embers
            dy = int(math.sin(phase) * 3)
            frame.paste(base_im, (0, dy), base_im)
            
            draw = ImageDraw.Draw(frame)
            for lf_i in range(5):
                ly = (320 + lf_i * 75 - t * 250) % 640
                lx = 320 + math.sin(phase + lf_i * 1.2) * (212 + lf_i * 15)
                la = int(210 * (0.5 + 0.5 * math.sin(phase + lf_i)))
                color = (255, 175, 45, la) if lf_i % 2 == 0 else (255, 95, 45, la)
                draw.ellipse((lx - 3, ly - 3, lx + 3, ly + 3), fill=color)

        elif anim_type == "anger":
            # Rhythmic anger pulse + electric impact sparks
            pulse = math.sin(phase * 2)
            scale = 1.0 + (0.055 * max(0.0, pulse))
            sw, sh = int(TARGET_SIZE * scale), int(TARGET_SIZE * scale)
            res = base_im.resize((sw, sh), Image.Resampling.BILINEAR)
            frame.paste(res, ((TARGET_SIZE - sw) // 2, (TARGET_SIZE - sh) // 2), res)
            
            draw = ImageDraw.Draw(frame)
            if pulse > 0.25:
                draw.line((490, 110, 515, 100), fill=(255, 55, 55, 230), width=3)
                draw.line((500, 140, 530, 135), fill=(255, 55, 55, 230), width=3)

        elif anim_type == "eclipse":
            # Solar corona plasma swirl
            frame.paste(base_im, (0, 0), base_im)
            glow = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            ga = int(95 + 45 * math.sin(phase))
            gd.ellipse((320 - 232, 320 - 232, 320 + 232, 320 + 232), outline=(255, 145, 25, ga), width=10)
            glow = glow.filter(ImageFilter.GaussianBlur(8))
            frame = Image.alpha_composite(glow, frame)

        elif anim_type == "wings":
            # Fluttering luminous wings
            scale_x = 1.0 + 0.045 * math.sin(phase)
            sw = int(TARGET_SIZE * scale_x)
            res = base_im.resize((sw, TARGET_SIZE), Image.Resampling.BILINEAR)
            frame.paste(res, ((TARGET_SIZE - sw) // 2, 0), res)

        else:
            dy = int(math.sin(phase) * 3)
            frame.paste(base_im, (0, dy), base_im)

        # Re-clear inner circle on every single frame to guarantee 100% clean aperture
        fpix = frame.load()
        for fy in range(320 - INNER_RADIUS, 320 + INNER_RADIUS + 1):
            for fx in range(320 - INNER_RADIUS, 320 + INNER_RADIUS + 1):
                dx = fx - 320
                dy = fy - 320
                if dx*dx + dy*dy < INNER_RADIUS * INNER_RADIUS:
                    fpix[fx, fy] = (0, 0, 0, 0)
                    
        frames.append(frame)

    return frames

def main():
    artworks_map = [
        ("fr_dc_horror_maw", "frame_monster_teeth_1791911177955.jpg", "breathe", 25, 20),
        ("fr_dc_horror_eyes", "frame_manga_eyes_1791911194447.jpg", "eyes", 20, 20),
        ("fr_dc_fox_ears", "frame_cute_cat_1791911213719.jpg", "cat_ears", 25, 20),
        ("fr_dc_white_roses", "frame_silver_roses_1791911233371.jpg", "roses", 22, 20),
        ("fr_dc_wolf_moon", "crescent_moon_celestial_frame_1791911178814.jpg", "moon", 22, 20),
        ("fr_dc_hades", "ghoul_claws_shadow_frame_1791911202496.jpg", "breathe", 25, 20),
        ("fr_dc_pumpkins", "autumn_leaves_sleeping_cat_frame_v2_1791911239134.jpg", "leaves", 25, 20),
        ("fr_dc_sparks", "anime_anger_shockwave_frame_1791911257022.jpg", "anger", 25, 20),
        ("fr_dc_snow_leopard", "frame_raccoon_1791911179002.jpg", "cat_ears", 25, 20),
        ("fr_dc_solar_eclipse", "frame_solar_eclipse_1791911210643.jpg", "eclipse", 25, 20),
        ("fr_dc_dark_roses", "frame_fairy_moth_wings_1791911226936.jpg", "wings", 22, 20),
        ("fr_dc_witch_hat", "frame_spooky_ghoul_1791911242931.jpg", "breathe", 25, 20),
    ]

    for item_id, file_name, anim, bg_th, soft_r in artworks_map:
        raw_path = os.path.join(RAW_DIR, file_name)
        if not os.path.exists(raw_path):
            print(f"ERROR: {raw_path} not found!")
            continue
            
        print(f"Processing artwork for {item_id} from {file_name}...")
        matted = clean_and_matte_artwork(raw_path, bg_thresh=bg_th, soft_range=soft_r)
        frames = generate_animation_frames(matted, anim)
        
        # Save animated WebP
        webp_path = os.path.join(MEDIA_DIR, f"{item_id}.webp")
        frames[0].save(webp_path, format="WEBP", save_all=True, append_images=frames[1:], duration=65, loop=0, quality=92)
        
        # Save master PNG
        png_path = os.path.join(MEDIA_DIR, f"{item_id}.png")
        frames[0].save(png_path, format="PNG")
        print(f"SUCCESS: {item_id}.webp & {item_id}.png created!")

    # Update database
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
        cur.execute(
            "UPDATE shop_items SET title = ?, description = ?, media_url = ?, preview_url = ?, media_kind = 'image' WHERE id = ?",
            (title, desc, f"/media/shop/{item_id}.webp", f"/media/shop/{item_id}.webp", item_id)
        )
    conn.commit()
    conn.close()
    print("ALL 12 MASTER ORIGINAL ARTWORKS PROCESSED & SHOP DATABASE UPDATED!")

if __name__ == "__main__":
    main()
