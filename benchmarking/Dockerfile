FROM ubuntu:24.04

RUN apt update && apt install -y time iproute2 tcpdump sysstat linux-tools-common linux-tools-generic cpulimit numactl cgroup-tools net-tools nano

#COPY ./liboqs-0.14.0.tar.gz ./0.14.0.tar.gz
#COPY ./openssl-3.5.2.tar.gz ./openssl-3.5.2.tar.gz

RUN apt update && apt install -y cmake ninja-build doxygen wget perl python3 python3-pip git&& \
	echo "---- apt install successful" && \
	\
    wget https://github.com/openssl/openssl/releases/download/openssl-3.5.2/openssl-3.5.2.tar.gz && \
	tar xf openssl-3.5.2.tar.gz && cd openssl-3.5.2 && \
	./config --prefix=/opt/openssl-3.5.2 --openssldir=/opt/openssl-3.5.2 && \
	make -j$(nproc) && make install_sw && make install_ssldirs && \
	echo "---- openssl installed" && \
	cd / && \
    wget https://github.com/open-quantum-safe/liboqs/archive/refs/tags/0.14.0.tar.gz && \
	tar xf 0.14.0.tar.gz && cd liboqs-0.14.0 && mkdir build && cd build && \
	cmake .. -GNinja \
	  -DCMAKE_INSTALL_PREFIX=/usr/local \
	  -DBUILD_SHARED_LIBS=ON \
	  -DBUILD_TESTING=OFF \
	  -DBUILD_EXAMPLES=OFF \
	  -DOQS_ENABLE_KEM_HQC=ON \
	  -DOPENSSL_ROOT_DIR=/opt/openssl-3.5.2 \
	  -DOPENSSL_INCLUDE_DIR=/opt/openssl-3.5.2/include \
	  -DOPENSSL_CRYPTO_LIBRARY=/opt/openssl-3.5.2/lib64/libcrypto.so && \
	ninja -j$(nproc) && ninja install && \
	echo "---- liboqs installed" && \
	cd / && \
	git clone -b IFN712 --single-branch https://github.com/JoshuaSowerby/IFN712-oqs-provider.git && \
	cd /IFN712-oqs-provider && \
	pip install -r /IFN712-oqs-provider/oqs-template/requirements.txt --break-system-packages && \	
	echo "---- pip install successful" && \
	export LIBOQS_SRC_DIR=/liboqs-0.14.0 && \
	python3 /IFN712-oqs-provider/oqs-template/generate.py && \
	echo "---- generate.py successful" && \
	mkdir build && cd build && \
	cmake .. -GNinja \
	  -DOPENSSL_ROOT_DIR=/opt/openssl-3.5.2 \
	  -DOPENSSL_INCLUDE_DIR=/opt/openssl-3.5.2/include \
	  -DOPENSSL_CRYPTO_LIBRARY=/opt/openssl-3.5.2/lib64/libcrypto.so \
	  -DCMAKE_INSTALL_PREFIX=/opt/openssl-3.5.2 && \
	ninja -j$(nproc) && ninja install && \
	echo "---- oqs-provider installed" && \
	cd / && \
	export LD_LIBRARY_PATH=/opt/openssl-3.5.2/lib64/ && \
	export PATH=/opt/openssl-3.5.2/bin:$PATH && \
	echo "/usr/local/lib" > /etc/ld.so.conf.d/liboqs.conf && \
	ldconfig &&  echo "---- done, don't forget /opt/openssl-3.5.2/openssl.cnf"

COPY ./openssl.cnf /opt/openssl-3.5.2/openssl.cnf
ENV LD_LIBRARY_PATH=/opt/openssl-3.5.2/lib64/
ENV PATH=/opt/openssl-3.5.2/bin:$PATH
ENV LIBOQS_SRC_DIR=/liboqs-0.14.0
