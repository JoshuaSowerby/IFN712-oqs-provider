#!/bin/bash

all_pq_kems=("frodo640shake" "frodo976shake" "frodo1344shake" "bikel1" "bikel3" "bikel5" "mlkem512" "mlkem768" "mlkem1024" "hqc128" "hqc192" "hqc256")
all_cl_kems=("x25519" "x448" "p256" "p384" "p521")

# Classical signature types
all_cl_sigs=("rsa:3072" "ed25519" "ed448")
# EC curves separated for dynamic generation
all_ec_curves=("prime256v1" "secp384r1" "secp521r1")

trap 'kill 0' SIGINT  # cleanup all background processes on Ctrl+C

mkdir -p logs

# 1️ Generate classical (non-EC) key/cert
for cl_sig in "${all_cl_sigs[@]}"; do
    openssl req -x509 -newkey "$cl_sig" \
        -keyout "key_${cl_sig}.pem" -out "cert_${cl_sig}.pem" \
        -days 365 -nodes -subj "/CN=oqs-server"
done

# 2️ Generate EC keys/certs dynamically
for curve in "${all_ec_curves[@]}"; do
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:$curve \
        -keyout "key_ec_${curve}.pem" -out "cert_ec_${curve}.pem" \
        -days 365 -nodes -subj "/CN=oqs-server"
done

# 3️ Benchmarking loop
for cl_sig in "${all_cl_sigs[@]}" "${all_ec_curves[@]/#/ec:}"; do
    # Determine key/cert file names
    if [[ "$cl_sig" == ec:* ]]; then
        curve="${cl_sig#ec:}"
        keyfile="key_ec_${curve}.pem"
        certfile="cert_ec_${curve}.pem"
        signame="$cl_sig"
    else
        keyfile="key_${cl_sig}.pem"
        certfile="cert_${cl_sig}.pem"
        signame="$cl_sig"
    fi

    for pq_kem in "${all_pq_kems[@]}"; do
        for cl_kem in "${all_cl_kems[@]}"; do
            hybrid_kem="${cl_kem}_${pq_kem}"
            combo_dir="logs/${signame}_${hybrid_kem}"
            mkdir -p "$combo_dir"

            echo "Starting test: $signame / $hybrid_kem"

            PORT=$((4000 + RANDOM % 1000))
            SEQ=0

            # Start server with sequence numbers in output
            openssl s_server -cert "$certfile" -key "$keyfile" \
                -accept "$PORT" -quiet -groups "$hybrid_kem" \
                > >(while IFS= read -r line; do
                        printf "[%04d] %s\n" "$SEQ" "$line"
                        ((SEQ++))
                    done > "$combo_dir/s_server.log") 2>&1 &
            SERVER_PID=$!
            sleep 2

            # Run client iterations with sequence numbers
            for i in {1..1000}; do
                printf "[%04d] Starting iteration\n" "$i" >> "$combo_dir/s_client.log"
				#(d)encaps not saving, maybe only exit the loop on server shutdown, limit connections to 1000
                /usr/bin/time -v openssl s_client -connect "localhost:$PORT" -groups "$hybrid_kem" -quiet \
                    >> "$combo_dir/s_client.log" \
                    2> >(grep -E "User time|System time|Elapsed|Percent of CPU|Maximum resident set size" \
                    | while IFS= read -r line; do
                        printf "[%04d] %s\n" "$i" "$line"
                    done >> "$combo_dir/s_client_perf.log")
            done

            # Kill server if running
            if [ ! -z "$SERVER_PID" ] && ps -p $SERVER_PID > /dev/null; then
                kill $SERVER_PID
            fi
            sleep 2
        done
    done
done
