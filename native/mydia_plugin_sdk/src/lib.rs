//! Mydia plugin authoring SDK.
//!
//! Typed WASM component-model bindings (generated from `wit/plugin.wit`, the
//! single source of truth shared with the Elixir host) plus the
//! `#[mydia::plugin]` attribute macro that lets an author write a plain typed
//! event handler.
//!
//! The generated bindings (`wit_bindgen::generate!`) and the macro land in U5/U6.
