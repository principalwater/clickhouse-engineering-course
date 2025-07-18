<?xml version="1.0"?>
<clickhouse replace="true">
    <profiles>
        <${super_user_name}>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>in_order</load_balancing>
            <log_queries>1</log_queries>
        </${super_user_name}>
        <${bi_user_name}>
            <max_memory_usage>500000000</max_memory_usage>
            <readonly>1</readonly>
            <load_balancing>random</load_balancing>
        </${bi_user_name}>
    </profiles>
    <users>
        <${super_user_name}>
            <password_sha256_hex>${super_user_password_sha256}</password_sha256_hex>
            <profile>${super_user_name}</profile>
            <networks>
                <ip>::1</ip> <!-- IPv6 localhost -->
                <ip>127.0.0.1</ip> <!-- IPv4 localhost -->
                <ip>::/0</ip>
            </networks>
            <quota>${super_user_name}</quota>
            <access_management>1</access_management>
            <named_collection_control>1</named_collection_control>
            <show_named_collections>1</show_named_collections>
            <show_named_collections_secrets>1</show_named_collections_secrets>
        </${super_user_name}>
        <${bi_user_name}>
            <password_sha256_hex>${bi_user_password_sha256}</password_sha256_hex>
            <profile>${bi_user_name}</profile>
            <networks>
                <ip>::/0</ip>
            </networks>
            <quota>${bi_user_name}</quota>
            <readonly>1</readonly>
        </${bi_user_name}>
        <!-- Полностью удаляем стандартного пользователя default (без этого cluster-auth по TCP может ругаться на несуществующего default) -->
        <default remove="true"/>
    </users>
    <quotas>
        <${super_user_name}>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </${super_user_name}>
        <${bi_user_name}>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </${bi_user_name}>
    </quotas>
</clickhouse>