ARG BASE_IMAGE_TAG=16-3.4

FROM postgis/postgis:$BASE_IMAGE_TAG AS base-image

ENV ORACLE_HOME=/usr/lib/oracle/client
ENV PATH=$PATH:${ORACLE_HOME}
ENV PG_MAJOR=16


FROM base-image AS basic-deps

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		ca-certificates \
        curl \
# (unless the parent stage cache is not invalidated...)
	gcc \
	make \
	postgresql-server-dev-$PG_MAJOR


FROM basic-deps AS mssqlodbc-deps

RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y msodbcsql17 msodbcsql18 mssql-tools mssql-tools18 unixodbc-dev


FROM basic-deps AS build-oracle_fdw

# Latest version
ARG ORACLE_CLIENT_URL=https://download.oracle.com/otn_software/linux/instantclient/instantclient-basic-linuxx64.zip
ARG ORACLE_SQLPLUS_URL=https://download.oracle.com/otn_software/linux/instantclient/instantclient-sqlplus-linuxx64.zip
ARG ORACLE_SDK_URL=https://download.oracle.com/otn_software/linux/instantclient/instantclient-sdk-linuxx64.zip

RUN apt-get install -y --no-install-recommends unzip && \
	# instant client
	curl -L -o instant_client.zip ${ORACLE_CLIENT_URL} && \
	unzip instant_client.zip -x META-INF/* && \
	# sqlplus
	curl -L -o sqlplus.zip ${ORACLE_SQLPLUS_URL} && \
	unzip sqlplus.zip -x META-INF/* && \
	# sdk
	curl -L -o sdk.zip ${ORACLE_SDK_URL} && \
	unzip sdk.zip -x META-INF/* && \
	# install
	mkdir -p ${ORACLE_HOME} && \
	mv ./instantclient_*/* ${ORACLE_HOME}

# Install oracle_fdw
WORKDIR /tmp/oracle_fdw
RUN ASSET_NAME=$(basename $(curl -LIs -o /dev/null -w %{url_effective} https://github.com/laurenz/oracle_fdw/releases/latest)) && \
	curl -L "https://github.com/laurenz/oracle_fdw/archive/${ASSET_NAME}.tar.gz" | tar -zx --strip-components=1 -C . && \
	make && \
	make install


FROM base-image AS final-stage

# libaio1 is a runtime requirement for the Oracle client that oracle_fdw uses
# libsqlite3-mod-spatialite is a runtime requirement for using spatialite with sqlite_fdw
RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		libaio1 \
		locales-all \
		libsqlite3-mod-spatialite \
		pgagent \
		postgresql-$PG_MAJOR-asn1oid \
		postgresql-$PG_MAJOR-debversion \
		postgresql-$PG_MAJOR-dirtyread \
		postgresql-$PG_MAJOR-extra-window-functions \
		postgresql-$PG_MAJOR-first-last-agg \
		postgresql-$PG_MAJOR-hll \
		postgresql-$PG_MAJOR-icu-ext \
		postgresql-$PG_MAJOR-ip4r \
		postgresql-$PG_MAJOR-jsquery \
		postgresql-$PG_MAJOR-mysql-fdw \
		postgresql-$PG_MAJOR-numeral \
		postgresql-$PG_MAJOR-ogr-fdw \
		postgresql-$PG_MAJOR-orafce \
		# postgresql-$PG_MAJOR-partman \
		postgresql-$PG_MAJOR-periods \
		postgresql-$PG_MAJOR-pg-fact-loader \
		postgresql-$PG_MAJOR-pgaudit \
		postgresql-$PG_MAJOR-pgfincore \
		postgresql-$PG_MAJOR-pgl-ddl-deploy \
		postgresql-$PG_MAJOR-pglogical \
		postgresql-$PG_MAJOR-pglogical-ticker \
		postgresql-$PG_MAJOR-pgmemcache \
		postgresql-$PG_MAJOR-pgmp \
		postgresql-$PG_MAJOR-pgpcre \
		postgresql-$PG_MAJOR-pgq-node \
		postgresql-$PG_MAJOR-pgrouting \
        postgresql-$PG_MAJOR-pgrouting-scripts \
		# postgresql-$PG_MAJOR-pgsphere \
		postgresql-$PG_MAJOR-pgtap \
		postgresql-$PG_MAJOR-pldebugger \
		# postgresql-$PG_MAJOR-pljava \
		# postgresql-$PG_MAJOR-pllua \
		postgresql-$PG_MAJOR-plpgsql-check \
		postgresql-$PG_MAJOR-plproxy \
		# postgresql-$PG_MAJOR-plr \
		postgresql-$PG_MAJOR-plsh \
		postgresql-$PG_MAJOR-pointcloud \
		postgresql-$PG_MAJOR-prefix \
		# postgresql-$PG_MAJOR-preprepare \
		postgresql-$PG_MAJOR-prioritize \
		# postgresql-$PG_MAJOR-python3-multicorn \
		# postgresql-$PG_MAJOR-q3c \
		postgresql-$PG_MAJOR-rational \
		postgresql-$PG_MAJOR-repack \
		postgresql-$PG_MAJOR-rum \
		postgresql-$PG_MAJOR-semver \
		postgresql-$PG_MAJOR-similarity \
		postgresql-$PG_MAJOR-tablelog \
		postgresql-$PG_MAJOR-tdigest \
		postgresql-$PG_MAJOR-tds-fdw \
		postgresql-$PG_MAJOR-toastinfo \
		postgresql-$PG_MAJOR-unit \
		# postgresql-$PG_MAJOR-wal2json \
		postgresql-plperl-$PG_MAJOR \
		postgresql-plpython3-$PG_MAJOR && \
	apt-get purge -y --auto-remove && \
	rm -rf /var/lib/apt/lists/*

COPY --from=mssqlodbc-deps \
	/opt/microsoft/ \
	/opt/microsoft/
COPY --from=mssqlodbc-deps \
	/opt/mssql-tools/ \
	/opt/mssql-tools/
COPY --from=mssqlodbc-deps \
	/usr/share/doc/msodbcsql17/ \
	/usr/share/doc/msodbcsql17/
COPY --from=mssqlodbc-deps \
	/etc/odbcinst.ini \
	/etc/odbcinst.ini

COPY --from=build-oracle_fdw \
	/usr/share/postgresql/$PG_MAJOR/extension/oracle_fdw* \
	/usr/share/postgresql/$PG_MAJOR/extension/
COPY --from=build-oracle_fdw \
	/usr/share/doc/postgresql-doc-$PG_MAJOR/extension/README.oracle_fdw \
	/usr/share/doc/postgresql-doc-$PG_MAJOR/extension/README.oracle_fdw
COPY --from=build-oracle_fdw \
	/usr/lib/postgresql/$PG_MAJOR/lib/oracle_fdw.so \
	/usr/lib/postgresql/$PG_MAJOR/lib/oracle_fdw.so
COPY --from=build-oracle_fdw  ${ORACLE_HOME}  ${ORACLE_HOME}

RUN echo ${ORACLE_HOME} > /etc/ld.so.conf.d/oracle_instantclient.conf && \
	ldconfig

COPY ./conf.sh  /docker-entrypoint-initdb.d/z_conf.sh
