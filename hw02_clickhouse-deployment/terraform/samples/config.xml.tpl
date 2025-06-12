<clickhouse replace="true">
    <logger>
        <level>debug</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>3</count>
    </logger>
    <display_name>${cluster_name} node ${node.shard}${node.replica}</display_name>
    <listen_host>0.0.0.0</listen_host>
    <http_port>${node.http_port}</http_port>
    <tcp_port>${node.tcp_port}</tcp_port>
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