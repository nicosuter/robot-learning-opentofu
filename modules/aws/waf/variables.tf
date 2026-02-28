variable "name_prefix" {
  description = "Prefix used for all WAF resource names"
  type        = string
}

variable "as214770_cidrs" {
  description = "IP prefixes announced by AS214770 (IPv4 and IPv6 mixed, e.g. [\"1.2.3.0/24\", \"2001:db8::/32\"]). Obtain current prefixes from https://bgp.he.net/AS214770 or your RIR."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to WAF resources"
  type        = map(string)
  default     = {}
}
