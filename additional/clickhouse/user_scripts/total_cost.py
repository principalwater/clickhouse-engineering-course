#!/usr/bin/env python3
import sys

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        price_str, quantity_str = line.split('\t')
        price = float(price_str)
        quantity = int(quantity_str)
        total = price * quantity
        print(f"{total:.2f}")
        sys.stdout.flush()
    except Exception as e:
        print('error', file=sys.stderr)