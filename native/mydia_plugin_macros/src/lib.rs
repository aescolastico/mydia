//! Proc-macros for the Mydia plugin SDK.
//!
//! Re-exported as `mydia_plugin_sdk::plugin`; authors use it through the SDK, not
//! this crate directly.

use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, ItemFn};

/// Turn a plain handler function into a Mydia plugin component.
///
/// The annotated function must have the signature
/// `fn(mydia_plugin_sdk::types::Event) -> Result<String, String>`. The macro
/// implements the generated `Guest` trait by calling it and emits the
/// component export, so the author never writes the trait impl or the export
/// wiring.
///
/// ```ignore
/// #[mydia_plugin_sdk::plugin]
/// fn on_event(evt: mydia_plugin_sdk::types::Event) -> Result<String, String> {
///     Ok("{}".into())
/// }
/// ```
#[proc_macro_attribute]
pub fn plugin(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let func = parse_macro_input!(item as ItemFn);
    let fn_name = &func.sig.ident;

    let expanded = quote! {
        #func

        #[doc(hidden)]
        struct __MydiaPluginImpl;

        impl ::mydia_plugin_sdk::Guest for __MydiaPluginImpl {
            fn on_event(
                evt: ::mydia_plugin_sdk::types::Event,
            ) -> ::core::result::Result<::std::string::String, ::std::string::String> {
                #fn_name(evt)
            }
        }

        ::mydia_plugin_sdk::export_plugin!(__MydiaPluginImpl);
    };

    expanded.into()
}
