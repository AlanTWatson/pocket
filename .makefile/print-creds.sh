#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
IFS=$'\n\t\v'

if [[ -z "${KUBECTL:-}" ]]; then
	if >/dev/null 2>&1 command -v kubectl; then
		KUBECTL=$(command -v kubectl)
	else
		>&2 echo "kubectl not found"
		exit 1
	fi
fi

KUBECTL_SERVER=$(${KUBECTL} config view --minify -o=jsonpath='{.clusters[0].cluster.server}' | cut -d ':' -f2 | cut -d '/' -f3 | tr -d '\n')

# get the IP where services are accessible over their nodePort bindings
NODEPORT_IP=${KUBECTL_SERVER}
if [[ "${NODEPORT_IP}" == "127.0.0.1" ]]; then
  # if it's a local setup, use local ip (that is connected to the default gateway)
  NODEPORT_IP=$(ip -4 addr show dev "$(awk '$2 == 00000000 { print $1 }' /proc/net/route)" | awk '$1 ~ /^inet/ { sub("/.*", "", $2); print $2 }' | head -1)
fi

function eck_creds() {
  if ! ${KUBECTL} -n monitoring get secret dune-eck-es-elastic-user 2>/dev/null >&2; then
    echo -n "waiting for ECK to start"
    while ! ${KUBECTL} -n monitoring get secret dune-eck-es-elastic-user 2>/dev/null >&2; do 
      echo -n "."
      sleep 1s
    done
    echo ""
  fi
	echo ""
	echo -e "\e[34mElasticsearch\e[0m"
	echo -n "	URL (in-cluster): https://elasticsearch.monitoring:"
	${KUBECTL} -n monitoring get service elasticsearch -ojsonpath='{.spec.ports[0].port}'; echo

	echo -n "	URL (out-cluster): https://${NODEPORT_IP}:"
	${KUBECTL} -n monitoring get service elasticsearch -ojsonpath='{.spec.ports[0].nodePort}'; echo

	echo -n "	User: elastic"
	echo -n "	Password: "
	${KUBECTL} get -n monitoring secret dune-eck-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo

	echo -e "\e[34mKibana\e[0m"
	echo -n "	URL (in-cluster): https://kibana.monitoring:"
	${KUBECTL} -n monitoring get service kibana -ojsonpath='{.spec.ports[0].port}'; echo

	echo -n "	URL (out-cluster): https://${NODEPORT_IP}:"
	${KUBECTL} -n monitoring get service kibana -ojsonpath='{.spec.ports[0].nodePort}'; echo

	echo -n "	User: elastic"
	echo -n "	Password: "
	${KUBECTL} get -n monitoring secret dune-eck-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo
}

function opmon_creds() {
  echo -e "\e[34mGrafana\e[0m"
	echo -n "	URL (in-cluster): http://grafana.monitoring:"
	${KUBECTL} -n monitoring get service grafana -ojsonpath='{.spec.ports[0].port}'; echo

	echo -n "	URL (out-cluster): http://${NODEPORT_IP}:"
	${KUBECTL} -n monitoring get service grafana -ojsonpath='{.spec.ports[0].nodePort}'; echo

	echo -n "	User: dune"
	echo -n "	Password: "
	${KUBECTL} get -n monitoring secret grafana-secrets -o=jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 --decode; echo

	echo -e "\e[34mInfluxDB\e[0m"
	echo -n "	URL (in-cluster): http://influxdb.monitoring:"
	${KUBECTL} -n monitoring get service influxdb -ojsonpath='{.spec.ports[0].port}'; echo

	echo -n "	URL (out-cluster): http://${NODEPORT_IP}:"
	${KUBECTL} -n monitoring get service influxdb -ojsonpath='{.spec.ports[0].nodePort}'; echo

	echo -n "	User: "
	${KUBECTL} get -n monitoring secret influxdb-secrets -o=jsonpath='{.data.INFLUXDB_READ_USER}' | base64 --decode;
	echo -n "	Password: "
	${KUBECTL} get -n monitoring secret influxdb-secrets -o=jsonpath='{.data.INFLUXDB_READ_USER_PASSWORD}' | base64 --decode; echo

	echo -n "	User: "
	${KUBECTL} get -n monitoring secret influxdb-secrets -o=jsonpath='{.data.INFLUXDB_USER}' | base64 --decode;
	echo -n "	Password: "
	${KUBECTL} get -n monitoring secret influxdb-secrets -o=jsonpath='{.data.INFLUXDB_USER_PASSWORD}' | base64 --decode; echo

	echo -n "	User: "
	${KUBECTL} get -n monitoring secret influxdb-secrets -o=jsonpath='{.data.INFLUXDB_ADMIN_USER}' | base64 --decode;
	echo -n "	Password: "
	${KUBECTL} get -n monitoring secret influxdb-secrets -o=jsonpath='{.data.INFLUXDB_ADMIN_USER_PASSWORD}' | base64 --decode; echo
}

function dashboard_creds() {
  echo -e "\e[34mKubernetes dashboard\e[0m"
	echo "	URL (in-cluster): http://kubernetes-dashboard.kubernetes-dashboard"
	echo -n "	URL (out-cluster): http://${NODEPORT_IP}:"
	${KUBECTL} -n kubernetes-dashboard get service kubernetes-dashboard -ojsonpath='{.spec.ports[0].nodePort}'; echo
	echo "	Password: none. click 'skip' in login window"
}

echo "Available services:"

if >/dev/null 2>&1 ${KUBECTL} get crd/kibanas.kibana.k8s.elastic.co; then
  eck_creds
fi

if >/dev/null 2>&1 ${KUBECTL} -n monitoring get secret/grafana-secrets secret/influxdb-secrets; then
  opmon_creds
fi
dashboard_creds

echo ""
echo "These services are accessible over a proxy server at http://${KUBECTL_SERVER}:31000"
