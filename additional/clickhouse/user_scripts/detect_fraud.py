#!/usr/bin/env python3
import sys
from datetime import datetime

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        price, product_id, transaction_date = line.split('\t')
        price = float(price)
        product_id = int(product_id)
        date = datetime.strptime(transaction_date, "%Y-%m-%d")
        weekday = date.weekday()
        is_weekend = weekday >= 5

        # Простая логика: большая сумма + редкий товар + выходной
        if price > 2000 and product_id > 590 and is_weekend:
            print('potential_fraud')
        else:
            print('ok')
        sys.stdout.flush()
    except Exception as e:
        print('error', file=sys.stderr)