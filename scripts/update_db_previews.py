import sqlite3

c = sqlite3.connect('/opt/connecto-server/connecto.db')
items = c.execute("SELECT id, title, media_url, preview_url FROM shop_items WHERE id LIKE 'fr_dc_%'").fetchall()
for it in items:
    print(it)

# Update preview_url to png and media_url to webp so static previews are clean and fast!
for it in items:
    item_id = it[0]
    c.execute(
        "UPDATE shop_items SET media_url = ?, preview_url = ?, media_kind = 'image' WHERE id = ?",
        (f"/media/shop/{item_id}.webp", f"/media/shop/{item_id}.png", item_id)
    )
c.commit()
print("Updated all 12 items to media_url=.webp and preview_url=.png!")
