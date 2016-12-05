#cloud-config

coreos:
  units:
    - name: "${app_name}.service"
      enable: true
      command: "start"
      content: |
        [Unit]
        Description=${app_name}
        After=docker.service network.target
        Requires=docker.service docker.socket early-docker.target

        [Service]
        TimeoutStartSec=0
        ExecStartPre=-/usr/bin/docker kill ${app_name}
        ExecStartPre=-/usr/bin/docker rm ${app_name}
        ExecStartPre=/usr/bin/docker pull ${docker_image}
        ExecStart=/usr/bin/docker run -p ${http_port}:80 --name ${app_name} ${docker_image}

        [Install]
        WantedBy=multi-user.target
