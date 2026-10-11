#!/usr/bin/env python3
"""Shows that this repository is the code running at the mainnet vault.

Run `forge build` first. The script reads the runtime bytecode of `DarkVault` (src/DarkVault.sol,
which inherits src/DarkVaultCore.sol) from out/, fetches the code deployed at the vault address in
deployments/4663.json, and requires them to be identical, byte for byte, except for two things:

  * the immutables: the USDG, registry and verifier addresses the constructor stored. They are read
    back out of the deployed code and must equal, as a set, those in deployments/4663.json; then the
    vault's own getters (part of the code just shown to be identical) must return each address in
    its role: usdg(), registry(), transferVerifier(), withdrawVerifier();
  * the trailing CBOR metadata, a hash of the source file names and comments, which differs because
    this repository arranges the same code in two files.

Usage:  forge build && python3 script/verify-mainnet.py      (RPC_URL=<endpoint> to choose the RPC)
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEPLOY = json.load(open(os.path.join(ROOT, "deployments", "4663.json")))
ARTIFACT = os.path.join(ROOT, "out", "DarkVault.sol", "DarkVault.json")
RPCS = [u for u in (os.environ.get("RPC_URL"), "https://rpc.mainnet.chain.robinhood.com", "https://api.darkwallet.cash/v1/rpc") if u]


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    last = None
    for url in RPCS:
        try:
            out = subprocess.run(
                ["curl", "-sS", "--max-time", "30", "-H", "content-type: application/json", "-d", body, url],
                capture_output=True, text=True, check=True,
            ).stdout
            res = json.loads(out)
            if "result" in res:
                return res["result"], url
            last = res.get("error")
        except Exception as e:  # unreachable, or a non-JSON challenge page: try the next endpoint
            last = e
    sys.exit(f"could not read the chain: {last}")


def main():
    if not os.path.exists(ARTIFACT):
        sys.exit("run `forge build` first")
    chain_id, url = rpc("eth_chainId", [])
    if int(chain_id, 16) != DEPLOY["chainId"]:
        sys.exit(f"{url} is chain {int(chain_id, 16)}, not {DEPLOY['chainId']}")
    art = json.load(open(ARTIFACT))["deployedBytecode"]
    local = bytes.fromhex(art["object"][2:])
    refs = sorted((r["start"], r["length"]) for v in art["immutableReferences"].values() for r in v)
    code, url = rpc("eth_getCode", [DEPLOY["vault"], "latest"])
    chain = bytes.fromhex(code[2:])
    if len(chain) != len(local):
        sys.exit(f"MISMATCH: {len(local)} bytes here, {len(chain)} on chain")

    stored = {chain[s : s + n][-20:].hex() for s, n in refs}
    a, b = bytearray(local), bytearray(chain)
    for s, n in refs:
        a[s : s + n] = b[s : s + n] = bytes(n)
    meta = int.from_bytes(local[-2:], "big") + 2
    if a[:-meta] != b[:-meta]:
        i = next(i for i, (x, y) in enumerate(zip(a, b)) if x != y)
        sys.exit(f"MISMATCH: first difference at byte {i}")

    roles = {
        "usdg()": DEPLOY["usdg"],
        "registry()": DEPLOY["registry"],
        "transferVerifier()": DEPLOY["verifiers"]["transfer"],
        "withdrawVerifier()": DEPLOY["verifiers"]["withdraw"],
    }
    expected = {a.lower()[2:] for a in roles.values()}
    if stored != expected:
        sys.exit(f"MISMATCH: the deployed vault stores {sorted(stored)}, deployments/4663.json says {sorted(expected)}")
    # Which address sits in which role: ask the deployed vault through its own getters.
    selectors = json.load(open(ARTIFACT))["methodIdentifiers"]
    for fn, want in roles.items():
        got, _ = rpc("eth_call", [{"to": DEPLOY["vault"], "data": "0x" + selectors[fn]}, "latest"])
        if got[-40:].lower() != want.lower()[2:]:
            sys.exit(f"MISMATCH: {fn} returns 0x{got[-40:]}, deployments/4663.json says {want}")

    print(f"DarkVault {DEPLOY['vault']} on chain {DEPLOY['chainId']} (read from {url})")
    print(f"  runtime code   {len(chain):,} bytes, identical to this build (metadata hash excluded)")
    for fn, addr in roles.items():
        print(f"  {fn:<20} {addr}")
    print("OK: src/ is the code deployed on mainnet")


if __name__ == "__main__":
    main()
