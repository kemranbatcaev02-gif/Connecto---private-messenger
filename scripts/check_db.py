import sqlite3

c = sqlite3.connect('/opt/connecto-server/connecto.db')
cols = c.execute("PRAGMA table_info(user_items)").fetchall()
print("user_items columns:", cols)
items = c.execute("SELECT * FROM user_items").fetchall()
print("user_items rows:", len(items), items)
