package gobindings

//go:generate go run generation/generate/wrap.go default TokenGovernor token_governor latest
//go:generate go run generation/generate/wrap.go default BurnMintWithExternalMinterTokenPool burn_mint_with_external_minter_token_pool latest
//go:generate go run generation/generate/wrap.go default HybridWithExternalMinterTokenPool hybrid_with_external_minter_token_pool latest
//go:generate go run generation/generate/wrap.go default Stablecoin usd_stablecoin latest
//go:generate go run generation/generate/wrap.go default TransparentUpgradeableProxy transparent_upgradeable_proxy latest
//go:generate go run generation/generate/wrap.go default ProxyAdmin proxy_admin latest
