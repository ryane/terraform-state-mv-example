#cloud-config

coreos:
  units:
    - name: "${web_name}.service"
      enable: true
      command: "start"
      content: |
        [Unit]
        Description=${web_name}
        After=docker.service network.target
        Requires=docker.service docker.socket early-docker.target

        [Service]
        TimeoutStartSec=0
        ExecStartPre=-/usr/bin/docker kill ${web_name}
        ExecStartPre=-/usr/bin/docker rm ${web_name}
        ExecStartPre=/usr/bin/docker pull ${docker_image}
        ExecStart=/usr/bin/docker run -p ${http_port}:80 --name ${web_name} ${docker_image}

        [Install]
        WantedBy=multi-user.target
