# Todo
1. fix inconsistent timings
- finish automation
    - namespaces
    - tc
    - limit cpu and memory
    - tcpdump
    - data collection
- fix ecc signatures
- implement hybrid signatures
- implement custom key combiners


- Where OQS_KEM_keypair() is called → log keygen time.

- Where OQS_KEM_encaps() is called → log encaps time + ciphertext size.

- Where OQS_KEM_decaps() is called → log decaps time + secret size.

# errors
- some ECC not working.
## encapsulations for classical greater than Post Q
- In `oqs_qs_kem_encaps_keyslot` only time `OQS_KEM_encaps(...)`
- In `oqs_evp_kem_encaps_keyslot` start timer at the top of the function and include `EVP_PKEY_new()`, `EVP_PKEY_copy_parameters()`, `EVP_PKEY_set1_encoded_public_key()`, `EVP_PKEY_CTX_new_from_pkey()`, `EVP_PKEY_keygen_init()` and `EVP_PKEY_keygen()` plus the derive and encoding

# Key combiner
- leave this for later, if you have time do it, if not drop it

in file `oqs_kem.c`:
    func `oqs_qs_kem_encaps_keyslot` time:
        -`OQS_KEM_encaps`
    func `oqs_qs_kem_decaps_keyslot` time:
        - `OQS_KEM_decaps`
in file `oqs_hyb_kem.c`:
    func `oqs_evp_kem_encaps_keyslot` time:
        - all
    func `oqs_evp_kem_decaps_keyslot` time:
        - all
```oqs_hyb_kem_decaps
///should I time these 2 instead?
    ret = oqs_evp_kem_decaps_keyslot(vpkemctx, NULL, &secretLenClassical, NULL,
                                     0, oqsx_key->reverse_share ? 1 : 0);
    ON_ERR_SET_GOTO(ret <= 0, ret, OQS_ERROR, err);
    ret = oqs_qs_kem_decaps_keyslot(vpkemctx, NULL, &secretLenPQ, NULL, 0,
                                    oqsx_key->reverse_share ? 0 : 1);
```
## change to one of these
1. Protocol-level performance (recommended for real-world comparison)
Include everything needed to go from ciphertext → shared secret (i.e. timing at the hybrid wrapper or timing the entire oqs_*_decaps_keyslot call). This is what an application experiences.

2. Algorithmic / crypto-work comparison
Include only the core cryptographic math (e.g. EVP_PKEY_derive() for classical, OQS_KEM_decaps() for PQ). Exclude repeated object creation/copies so you compare raw algorithm cost.



# Signatures
- not implemented
# key combiners
- not implemented
- may have to have to reinstall per key combiner
At the end of `oqs_kem.c`
```
#define MAKE_HYB_KEM_FUNCTIONS(alg)                                            \
    const OSSL_DISPATCH oqs_##alg##_kem_functions[] = {                        \
        {OSSL_FUNC_KEM_NEWCTX, (void (*)(void))oqs_kem_newctx},                \
        {OSSL_FUNC_KEM_ENCAPSULATE_INIT, (void (*)(void))oqs_kem_encaps_init}, \
        {OSSL_FUNC_KEM_ENCAPSULATE, (void (*)(void))oqs_hyb_kem_encaps},       \
        {OSSL_FUNC_KEM_DECAPSULATE_INIT, (void (*)(void))oqs_kem_decaps_init}, \
        {OSSL_FUNC_KEM_DECAPSULATE, (void (*)(void))oqs_hyb_kem_decaps},       \
        {OSSL_FUNC_KEM_FREECTX, (void (*)(void))oqs_kem_freectx},              \
        {0, NULL}};

// keep this just in case we need to become ALG-specific at some point in time
MAKE_KEM_FUNCTIONS(generic)
MAKE_HYB_KEM_FUNCTIONS(hybrid)
```
Or from `oqsprov_keys.c`:
- `oqsx_key_set_composites`
- `oqsx_key_fromdata`
- `oqsx_key_set_composites`







Short answer: **It depends** — the *combination* happens either inside the KEM implementation (provider / EVP layer) **or** inside libssl before the TLS-1.3 key schedule. In OpenSSL’s source the places to look are:

---

## Where to inspect in the OpenSSL tree (concrete files)

* **TLS 1.3 key schedule / HKDF (where the combined secret is consumed)**
  `ssl/tls13_enc.c` — this is where TLS-1.3 derives secrets (HKDF / Derive-Secret / key/IV). This is the code that *uses* the shared secret(s) to derive the real keys. ([GitHub][1])

* **libssl glue that runs KEM ops in the handshake (construct/parse key shares, call encapsulate/decapsulate)**
  `ssl/statem/extensions_clnt.c` and `ssl/statem/extensions_srvr.c` — code that constructs/parses the TLS KeyShare / KEM keyshare extensions and drives the per-group operations. ([GitHub][2])

* **helper that performs encapsulation/decapsulation for libssl**
  `ssl/s3_lib.c` — contains `ssl_encapsulate` / related calls (this is where libssl calls into the EVP/KEM APIs during the handshake). Error traces you may have seen point here. ([GitHub][3])

* **EVP/KEM implementation layer (the API that providers implement / which actually does encapsulate/decapsulate)**
  `crypto/evp/kem.c` — the EVP-level KEM wrapper and helpers that call the provider’s implementation (EVP_PKEY_encapsulate, etc.). If a provider exposes a *single* hybrid KEM EVP_PKEY, the combination can be implemented here or in the provider. ([GitHub][4])

* **Design notes / documentation about ML-KEM and hybrids**
  `doc/designs/ML-KEM.md` and the multiple GH discussions/PRs about ML-KEM / hybrid KEM support — useful to read to understand the intended semantics (some hybrids are exposed as single algorithms; others are composed by libssl). ([GitHub][5])

---

## How to read that in practice (flow)

1. During the handshake libssl decides which key exchange group(s) to use (see `extensions_clnt.c` / `extensions_srvr.c`).
2. For *KEM* groups libssl calls into the KEM code path (via `ssl_encapsulate` in `s3_lib.c`), which in turn uses the EVP KEM APIs (`EVP_PKEY_encapsulate` / wrappers in `crypto/evp/kem.c`). ([GitHub][3])
3. **If the hybrid is implemented as a single EVP_PKEY algorithm** (e.g. `X25519MLKEM...` or an oqs-provider hybrid), that single `EVP_PKEY_encapsulate` call typically returns the *already-combined* secret/ciphertext according to the provider/algorithm definition — i.e. the provider/EVP code does the combination. (OpenSSL docs and discussions say hybrid can be exposed as “just another KEM”.) ([GitHub][6])
4. **If the hybrid is expressed as two separate primitive shares** (e.g. one ECDH share + one PQ KEM share exposed separately), libssl will perform both operations and then arrange the secrets into the input the key schedule expects (effectively concatenating/assembling them) *before* calling the TLS-1.3 key schedule (HKDF) in `ssl/tls13_enc.c`. The actual concatenation/assembly logic is in the handshake code paths that call the encapsulate/decapsulate helpers. ([GitHub][2])

---

## So: where *exactly* is the “combining” line of code?

* If you have a hybrid **EVP_PKEY** (provider exposes it as one algorithm): check the **provider** code or the EVP/KEM wrapper (`crypto/evp/kem.c`) — the provider/EVP code is where the shared secret is produced (already combined) and returned to libssl. ([GitHub][4])
* If the handshake uses **two separate keyshares** and libssl is the one doing both ops, look for where libssl calls `ssl_encapsulate`/encapsulation twice and then forms the `secret` buffer that gets handed to the TLS-1.3 KDF — those call sites live in `ssl/s3_lib.c` / `ssl/statem/*` and ultimately feed `ssl/tls13_enc.c`. ([GitHub][3])

---

## Useful places to grep in your local checkout

(If you want exact lines quickly on your machine)

* `git grep -n "ssl_encapsulate" ssl`
* `git grep -n "encapsulat" -n crypto/evp` (to find `EVP_PKEY_encapsulate` wrappers)
* Open `ssl/statem/extensions_clnt.c` / `extensions_srvr.c` and search for `key_share` / `KEM` / `MLKEM`
* Open `ssl/tls13_enc.c` and search for `derive_secret`, `HKDF` or `derive_secret_key_and_iv`

---

https://cupdev.net/blog/014_quantumhardening.html

## TL;DR (one-line)

* **The TLS HKDF code (tls13_enc.c) consumes the final secret.**
* **Who *combines* the primitive secrets?** either the *provider/EVP KEM* (for single-alg hybrids) **or** libssl (in the statem / s3_lib handshake code) if it performed multiple encapsulations and then concatenated them — so check `crypto/evp/kem.c`, `ssl/s3_lib.c`, and `ssl/statem/*.c`, then follow to `ssl/tls13_enc.c`. ([GitHub][4])

---

If you want, I can:

* give the exact `git grep` commands to run and paste the specific functions/line numbers from the version you have checked out (that’s the fastest way to find the exact lines in your local copy), or
* if you tell me which OpenSSL commit/tag (e.g. `OpenSSL_3_5_0`) and which provider (oqs-provider version), I’ll run targeted searches and point to exact functions/line numbers (and highlight the concatenation site if libssl does it).

[1]: https://github.com/openssl/openssl/blob/master/ssl/tls13_enc.c "openssl/ssl/tls13_enc.c at master · openssl/openssl · GitHub"
[2]: https://github.com/openssl/openssl/blob/master/ssl/statem/extensions_clnt.c?utm_source=chatgpt.com "openssl/ssl/statem/extensions_clnt.c at master - GitHub"
[3]: https://github.com/openssl/openssl/blob/master/ssl/s3_lib.c?utm_source=chatgpt.com "openssl/ssl/s3_lib.c at master · openssl/openssl · GitHub"
[4]: https://github.com/openssl/openssl/blob/master/crypto/evp/kem.c "openssl/crypto/evp/kem.c at master · openssl/openssl · GitHub"
[5]: https://github.com/openssl/openssl/blob/master/doc/designs/ML-KEM.md?utm_source=chatgpt.com "openssl/doc/designs/ML-KEM.md at master - GitHub"
[6]: https://github.com/openssl/openssl/discussions/26073?utm_source=chatgpt.com "OpenSSL API and OpenSSH ML-KEM support - GitHub"


---


---



all this ai stuff may not be true

Short answer: the provider builds / stores the per-component keys in the key-management code (the `oqsx_key_*` helpers in `oqsprov/oqsprov_keys.c`), and the KEM code then uses those stored component keys (`comp_pubkey` / `comp_privkey`) when it does encaps/decaps (the hybrid KEM glue is in `oqsprov/oqs_kem.c` / `oqs_hyb_kem.c`).

Where to look (exact files & symbols)

* `oqsprov/oqsprov_keys.c` — the functions that *assemble* hybrid/composite keys live here (look for `oqsx_key_set_composites`, `oqsx_key_fromdata`, etc.). An issue/PR discussion calls out `oqsx_key_set_composites` as the routine that populates the `comp_pubkey`/`comp_privkey` vectors after import. ([GitHub][1])
* `oqsprov/oqs_kem.c` (includes `oqs_hyb_kem.c`) — the KEM code reads the combined keys from the `OQSX_KEY` structure and calls liboqs encaps/decaps with `comp_pubkey`/`comp_privkey`. You can see the provider using `pkemctx->kem->comp_pubkey[...]` for encaps and `pkemctx->kem->comp_privkey[...]` for decaps. ([GitHub][2])
* Encoder / decoder code that serialises/deserialises hybrid/composite key blobs (how the component public/private bytes are concatenated / stored) lives in the provider encoders/decoders, e.g. `oqsprov/oqs_encode_key2any.c` and related decode helpers (`oqs_decode_der2key.c`). Those files implement the wire/DER layout for composite/hybrid keys. ([GitHub][3])

What “combined” actually means in this codebase

* The provider does **not** cryptographically mix the algorithms into a single new primitive; it **stores the component keys** (classical and PQ) together and exposes a hybrid key interface. The combination step is essentially: encode each component key → put them into arrays `comp_pubkey` / `comp_privkey` inside the `OQSX_KEY` structure → use those component buffers when performing encaps/decaps. The place that *populates* those component arrays is `oqsx_key_set_composites` / the key import/generation routines in `oqsprov_keys.c`. ([GitHub][1])

Quick grep commands to run locally (fast way to jump to the exact lines)

```bash
# find where component buffers are referenced
grep -nR "comp_pubkey" -n oqs-provider/oqsprov || true
grep -nR "comp_privkey" -n oqs-provider/oqsprov || true

# find the function that sets composites
grep -nR "oqsx_key_set_composites" -n oqs-provider || true

# open the KEM/hybrid glue
sed -n '1,240p' oqs-provider/oqsprov/oqs_kem.c
sed -n '1,240p' oqs-provider/oqsprov/oqs_hyb_kem.c
```

If you want help locating the *exact* lines to instrument:

* I can point you to the lines in `oqsprov_keys.c` that call `oqsx_key_set_composites` and show the code that fills `comp_pubkey` / `comp_privkey`.
* I can also point to the exact lines in `oqs_kem.c` / `oqs_hyb_kem.c` where the provider selects which component index to pass to liboqs’ `OQS_KEM_encaps` / `OQS_KEM_decaps` (good places to add timings).

Which of those would be most useful right now — (A) exact lines in `oqsprov_keys.c` that populate the composites, or (B) exact lines in the KEM/hybrid code where encaps/decaps use `comp_pubkey` / `comp_privkey` (good for timing/benchmarking)?

[1]: https://github.com/open-quantum-safe/oqs-provider/issues/148?utm_source=chatgpt.com "Key import is nonfunctional · Issue #148 · open-quantum-safe ... - GitHub"
[2]: https://github.com/open-quantum-safe/oqs-provider/blob/main/oqsprov/oqs_kem.c?utm_source=chatgpt.com "oqs-provider/oqsprov/oqs_kem.c at main · open-quantum-safe ... - GitHub"
[3]: https://github.com/open-quantum-safe/oqs-provider/blob/main/oqsprov/oqs_encode_key2any.c "oqs-provider/oqsprov/oqs_encode_key2any.c at main · open-quantum-safe/oqs-provider · GitHub"


# tc & cpu limit
- not implemented