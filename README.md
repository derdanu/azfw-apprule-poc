# Azure Firewall Apprule Testenvironment

Testing Application Ruleset SNAT 

## IPs

|IP| |
|-|-|
|10.0.0.4|Azure Firewall|
|10.1.0.4|Nginx|
|10.2.0.4|Client|


## Usage 
``` 
yourmaschine$ $(terraform output connect_cmd)
client$ curl web.poc.local
client$ ssh 10.1.0.4 cat /var/log/nginx/access.log
``` 