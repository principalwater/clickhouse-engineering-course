# gen_user_emails_csv.py
import csv
import os

# Укажи диапазон id согласно тестовому набору — от 1000 до 100999
START_ID = 1000
END_ID = 100999

# Пишем файл именно в samples/
out_path = os.path.join(os.path.dirname(__file__), "user_emails.csv")
with open(out_path, 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(['user_id', 'email'])
    for i in range(START_ID, END_ID + 1):
        writer.writerow([i, f'user{i}@example.com'])