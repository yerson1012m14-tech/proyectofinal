//! Remote Service Discovery
//! Communicates via XPC and returns advertised services

use std::collections::HashMap;

use serde::Deserialize;
use tracing::{debug, warn};

use crate::{IdeviceError, ReadWrite, RemoteXpcClient, provider::RsdProvider};

/// Describes an available XPC service
#[derive(Debug, Clone, Deserialize)]
pub struct RsdService {
    /// Required entitlement to access this service
    pub entitlement: String,
    /// Port number where the service is available
    pub port: u16,
    /// Whether the service uses remote XPC
    pub uses_remote_xpc: bool,
    /// Optional list of supported features
    pub features: Option<Vec<String>>,
    /// Optional service version number
    pub service_version: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct RsdHandshake {
    pub services: HashMap<String, RsdService>,
    /// Original advertised service values, retained for read-only diagnostics.
    pub advertised_services: plist::Dictionary,
    pub protocol_version: usize,
    pub properties: HashMap<String, plist::Value>,
    pub uuid: String,
}

fn parse_service_port(value: &plist::Value) -> Option<u16> {
    let port = if let Some(text) = value.as_string() {
        text.parse::<u16>().ok()?
    } else if let Some(number) = value.as_unsigned_integer() {
        u16::try_from(number).ok()?
    } else if let Some(number) = value.as_signed_integer() {
        u16::try_from(number).ok()?
    } else {
        return None;
    };
    (port != 0).then_some(port)
}

#[cfg(test)]
mod port_tests {
    use super::{parse_service_port, parse_services_dict};
    use plist::Value;

    #[test]
    fn accepts_port_string_and_integer_without_truncation() {
        assert_eq!(parse_service_port(&Value::String("49152".into())), Some(49152));
        assert_eq!(parse_service_port(&Value::Integer(49152_u64.into())), Some(49152));
        assert_eq!(parse_service_port(&Value::Integer(49152_i64.into())), Some(49152));
        assert_eq!(parse_service_port(&Value::Integer(65536_u64.into())), None);
        assert_eq!(parse_service_port(&Value::Integer((-1_i64).into())), None);
        assert_eq!(parse_service_port(&Value::String("0".into())), None);
    }

    #[test]
    fn retains_public_services_without_entitlement_and_preserves_xpc_flag() {
        let services = plist_macro::plist!({
            "com.apple.atc.shim.remote": { "Port": 49152 },
            "com.apple.streaming_zip_conduit.shim.remote": { "Port": "49153" },
            "xpc": { "Port": 49154, "Properties": { "UsesRemoteXPC": true } },
            "invalid": { "Port": 65536 },
        });
        let parsed = parse_services_dict(services.as_dictionary().unwrap());
        assert_eq!(parsed.len(), 3);
        assert_eq!(parsed["com.apple.atc.shim.remote"].entitlement, "");
        assert_eq!(parsed["com.apple.atc.shim.remote"].port, 49152);
        assert_eq!(parsed["com.apple.streaming_zip_conduit.shim.remote"].port, 49153);
        assert!(parsed["xpc"].uses_remote_xpc);
        assert!(!parsed.contains_key("invalid"));
    }
}

fn parse_services_dict(services_dict: &plist::Dictionary) -> HashMap<String, RsdService> {
    let mut services: HashMap<String, RsdService> = HashMap::new();
    for (name, service) in services_dict.into_iter() {
        match service.as_dictionary() {
            Some(service) => {
                // Public and shim services can omit Entitlement entirely.
                let entitlement = service.get("Entitlement")
                    .and_then(|x| x.as_string()).unwrap_or("").to_owned();
                let port = match service.get("Port").and_then(parse_service_port) {
                    Some(e) => e,
                    None => {
                        warn!("Service did not contain a valid nonzero port");
                        continue;
                    }
                };
                let uses_remote_xpc = match service
                    .get("Properties")
                    .and_then(|x| x.as_dictionary())
                    .and_then(|x| x.get("UsesRemoteXPC"))
                    .and_then(|x| x.as_boolean())
                {
                    Some(e) => e.to_owned(),
                    None => false, // default is false
                };

                let features = service
                    .get("Properties")
                    .and_then(|x| x.as_dictionary())
                    .and_then(|x| x.get("Features"))
                    .and_then(|x| x.as_array())
                    .map(|f| {
                        f.iter()
                            .filter_map(|x| x.as_string())
                            .map(|x| x.to_string())
                            .collect::<Vec<String>>()
                    });

                let service_version = service
                    .get("Properties")
                    .and_then(|x| x.as_dictionary())
                    .and_then(|x| x.get("ServiceVersion"))
                    .and_then(|x| x.as_signed_integer())
                    .map(|e| e.to_owned());

                services.insert(
                    name.to_string(),
                    RsdService {
                        entitlement,
                        port,
                        uses_remote_xpc,
                        features,
                        service_version,
                    },
                );
            }
            None => {
                warn!("Service is not a dictionary!");
                continue;
            }
        }
    }

    services
}

impl RsdHandshake {
    pub async fn new(socket: impl ReadWrite) -> Result<Self, IdeviceError> {
        let mut xpc_client = RemoteXpcClient::new(socket).await?;
        xpc_client.do_handshake().await?;
        xpc_client.send_device_handshake().await?;
        let data = xpc_client.recv_root().await?;

        let services_dict = match data
            .as_dictionary()
            .and_then(|x| x.get("Services"))
            .and_then(|x| x.as_dictionary())
        {
            Some(d) => d,
            None => {
                return Err(IdeviceError::UnexpectedResponse(
                    "missing Services dictionary in RSD handshake".into(),
                ));
            }
        };

        let services = parse_services_dict(services_dict);

        let protocol_version = match data.as_dictionary().and_then(|x| {
            x.get("MessagingProtocolVersion")
                .and_then(|x| x.as_signed_integer())
        }) {
            Some(p) => p as usize,
            None => {
                return Err(IdeviceError::UnexpectedResponse(
                    "missing MessagingProtocolVersion in RSD handshake".into(),
                ));
            }
        };

        let uuid = match data
            .as_dictionary()
            .and_then(|x| x.get("UUID").and_then(|x| x.as_string()))
        {
            Some(u) => u.to_string(),
            None => {
                return Err(IdeviceError::UnexpectedResponse(
                    "missing UUID in RSD handshake".into(),
                ));
            }
        };

        let properties = match data
            .as_dictionary()
            .and_then(|x| x.get("Properties").and_then(|x| x.as_dictionary()))
        {
            Some(d) => d
                .into_iter()
                .map(|(name, prop)| (name.to_owned(), prop.to_owned()))
                .collect::<HashMap<String, plist::Value>>(),
            None => {
                return Err(IdeviceError::UnexpectedResponse(
                    "missing Properties dictionary in RSD handshake".into(),
                ));
            }
        };

        Ok(Self {
            services,
            advertised_services: services_dict.clone(),
            protocol_version,
            properties,
            uuid,
        })
    }

    pub async fn connect<T>(&mut self, provider: &mut impl RsdProvider) -> Result<T, IdeviceError>
    where
        T: crate::RsdService,
    {
        let service_name = T::rsd_service_name();
        let service = match self.services.get(&service_name.to_string()) {
            Some(s) => s,
            None => {
                return Err(IdeviceError::ServiceNotFound);
            }
        };

        debug!(
            "Connecting to RSD service {service_name} on port {}",
            service.port
        );
        let stream = provider.connect_to_service_port(service.port).await?;
        T::from_stream(stream).await
    }
}
