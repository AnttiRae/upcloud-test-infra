variable "cloudflare_api_token" {}

variable "zone_id" {}

variable "account_id" {}

variable "domain" {}

variable "records" {
	type = map(object({
		type = string
		ttl = number
		ip = string
	}))
	default = {}
}
