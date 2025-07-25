<clickhouse replace="true">
    <logger>
        <level>debug</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>3</count>
    </logger>
    <display_name>${cluster_name} node ${node.shard} replica ${node.replica}</display_name>
    <listen_host>0.0.0.0</listen_host>
    <http_port>${ch_http_port}</http_port>
    <tcp_port>${ch_tcp_port}</tcp_port>
    <tcp_port_replication>${ch_replication_port}</tcp_port_replication>

    <!-- optimization part start -->
    <!-- Ограничения скорости репликации для стресс-тестов и прод-стенда -->
    <max_replicated_fetches_network_bandwidth_for_server>1073741824</max_replicated_fetches_network_bandwidth_for_server> <!-- 1 GB -->
    <max_replicated_sends_network_bandwidth_for_server>536870912</max_replicated_sends_network_bandwidth_for_server> <!-- 512 MB -->

    <merge_tree>
        <parts_to_throw_insert>300</parts_to_throw_insert> <!-- лимит на количество частей -->
        <min_rows_for_wide_part>0</min_rows_for_wide_part>
        <min_bytes_for_wide_part>0</min_bytes_for_wide_part>
        <write_ahead_log_max_bytes>1073741824</write_ahead_log_max_bytes> <!-- 1 GB -->
        <enable_mixed_granularity_parts>1</enable_mixed_granularity_parts>
        <replicated_can_become_leader>${node.replica == 1 ? 1 : 0}</replicated_can_become_leader> <!-- только для первой реплики в каждом шарде -->
    </merge_tree>
    <compression>
        <case>
            <min_part_size>1000000000</min_part_size>
            <method>zstd</method>
        </case>
        <case>
            <min_part_size>0</min_part_size>
            <method>lz4</method>
        </case>
    </compression>
    <query_log>
        <database>system</database>
        <table>query_log</table>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </query_log>
    <!-- optimization part end -->

    <user_directories>
        <users_xml>
            <path>users.xml</path>
        </users_xml>
        <local_directory>
            <path>/var/lib/clickhouse/access/</path>
        </local_directory>
    </user_directories>
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>
<remote_servers>
  <${cluster_name}>
%{ for shard in remote_servers ~}
    <shard>
    %{ for replica in shard.replicas ~}
      <replica>
        <host>${replica.host}</host>
        <port>${replica.port}</port>
        <user>${super_user_name}</user>
        <password>${super_user_password}</password>
      </replica>
    %{ endfor ~}
    </shard>
%{ endfor ~}
  </${cluster_name}>
</remote_servers>
    <zookeeper>
%{~ for keeper in keepers ~}
        <node>
            <host>${keeper.host}</host>
            <port>${keeper.tcp_port}</port>
        </node>
%{~ endfor ~}
    </zookeeper>
    <macros>
        <shard>0${node.shard}</shard>
        <replica>0${node.replica}</replica>
    </macros>
</clickhouse>
