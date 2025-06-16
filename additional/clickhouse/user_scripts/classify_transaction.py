#!/usr/bin/env python3
import sys

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        price, quantity, product_id, user_id = line.split('\t')
        price = float(price)
        quantity = int(quantity)
        product_id = int(product_id)
        user_id = int(user_id)
        total = price * quantity

        # Логика: крупная покупка, редкий товар, частый пользователь
        if total > 1000:
            print('large_purchase')
        elif product_id > 510:
            print('rare_product')
        elif user_id <= 120:
            print('frequent_buyer')
        else:
            print('regular')
        sys.stdout.flush()
    except Exception as e:
        print('error', file=sys.stderr)