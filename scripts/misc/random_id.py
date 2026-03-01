#!/usr/bin/env python
import random
import string

def id_generator(size=6, chars=string.ascii_letters + string.digits):
    return ''.join(random.choice(chars) for _ in range(size))

if __name__ == "__main__":
    print(id_generator(size=20))
