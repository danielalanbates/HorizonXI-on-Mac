#!/usr/bin/env python3
import json, os, socket, ssl, sys
USER = "danielalanbates"
PASS = json.load(open(os.path.expanduser(
    "~/Library/Application Support/HorizonXI-on-Mac/accounts.json")))[USER]
ctx = ssl.create_default_context()
ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
raw = socket.create_connection(("server.catseyexi.com", 54231), timeout=20)
s = ctx.wrap_socket(raw)
cmd = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x20  # LOGIN_CREATE
s.sendall(json.dumps({"command": cmd, "username": USER, "password": PASS}).encode())
resp = s.recv(4096)
print("raw:", resp[:200])
try:
    r = json.loads(resp.decode().rstrip("\x00"))
    codes = {0:"FAIL",1:"SUCCESS",2:"ERROR",3:"SUCCESS_CREATE",4:"CREATE_TAKEN",8:"CREATE_DISABLED",9:"ERROR_CREATE",0xA:"ALREADY_LOGGED_IN",0xB:"VERSION_UNSUPPORTED"}
    print("result:", r, codes.get(r.get("result"), "?"))
except Exception as e:
    print("parse:", e)
s.close()
