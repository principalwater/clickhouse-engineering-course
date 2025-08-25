<?xml version="1.0"?>
<clickhouse>
    <!-- Prometheus metrics endpoint configuration -->
    <prometheus>
        <!-- HTTP endpoint for Prometheus metrics -->
        <endpoint>/metrics</endpoint>
        
        <!-- Port for Prometheus endpoint -->
        <port>9363</port>
        
        <!-- Enable current system metrics -->
        <metrics>true</metrics>
        
        <!-- Enable event counters -->
        <events>true</events>
        
        <!-- Enable asynchronous system metrics -->
        <asynchronous_metrics>true</asynchronous_metrics>
        
        <!-- Enable error counters by error codes -->
        <errors>true</errors>
    </prometheus>
    
    <!-- Optional: HTTP handlers for custom metrics endpoints -->
    <http_handlers>
        <rule>
            <url>/metrics</url>
            <methods>GET</methods>
            <handler>
                <type>predefined_query_handler</type>
                <query>SELECT metric, value FROM system.asynchronous_metrics FORMAT Prometheus</query>
                <content_type>text/plain; charset=utf-8</content_type>
            </handler>
        </rule>
        <defaults/>
    </http_handlers>
</clickhouse>