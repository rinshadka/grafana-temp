local common = import "common.ccf-conf.jsonnet";
local context = import "context.ccf-facts.json";
local dockerFacts = import "eth0-interface-localhost.ccf-facts.json";
local traefikConf = import "traefikEventNav.ccf-conf.jsonnet";
local containerSecrets = import "grafana.secrets.ccf-conf.jsonnet";

local webServicePort = 3001;
local webServicePortInContainer = 3000;

{
	"docker-compose.yml" : std.manifestYamlDoc({
		version: '3.4',

		services: {
			container: {
				container_name: context.containerName,
				image: 'grafana/grafana:master',
				restart: 'always',
				ports: [webServicePort + ':' + webServicePortInContainer],
				networks: ['network'],
				volumes: [
					'storage:/var/lib/grafana',
					context.containerRuntimeConfigHome + '/provisioning:/etc/grafana/provisioning',
				],
				environment: [
					"GF_DEFAULT_INSTANCE_NAME=" + common.applianceName,
					"GF_SECURITY_ADMIN_USER=" + containerSecrets.adminUser,
					"GF_SECURITY_ADMIN_PASSWORD=" + containerSecrets.adminPassword,
					"GF_USERS_ALLOW_SIGN_UP=false",
                    "GF_EXPLORE_ENABLED=true"
				],
                labels: {
                        'traefik.enable': 'true',
                        'traefik.docker.network': common.defaultDockerNetworkName,
                        'traefik.domain': traefikConf.angularAppFQDN,
                        'traefik.backend': context.containerName,
                        'traefik.frontend.entryPoints': 'http',
                        'traefik.frontend.rule': 'Host:' + context.containerName + '.' + traefikConf.angularAppFQDN,
                }
			},
		},

		networks: {
			network: {
				external: {
					name: common.defaultDockerNetworkName
				},
			},
		},

		volumes: {
			storage: {
				name: context.containerName
			},
		},
	}),

    "after_configure.make-plugin.sh": |||
         #!/bin/bash
         GRAFANA_PROV_DASHBOARDS_HOME=etc/provisioning/dashboards
         echo "Replacing DS_PROMETHEUS with 'Prometheus' in $GRAFANA_PROV_DASHBOARDS_HOME"
         sed -i 's/$${DS_PROMETHEUS}/Prometheus/g' $GRAFANA_PROV_DASHBOARDS_HOME/*.json
         # Allow Grafana container to communicate to docker host through docker bridge network
         sudo ufw allow in on `echo br-$(docker network ls -f name=appliance | awk '{if (NR!=1) {print}}' | awk '{print $1}')` to any port 8010
     |||,

	"etc/provisioning/datasources/prometheus.yml" : std.manifestYamlDoc({
		apiVersion: 1,
		datasources: [
			{
				name: "Prometheus",
				type: "prometheus",
				access: "proxy",
				url: 'http://' + dockerFacts.address + ":" + 8010
			},
		],
	}),

    "etc/provisioning/datasources/loki.yml" : std.manifestYamlDoc({
         apiVersion: 1,
         datasources: [
             {
                 name: "Loki",
                 type: "loki",
                 access: "proxy",
                 url: 'http://loki:3100'
             },
         ],
     }),

}

