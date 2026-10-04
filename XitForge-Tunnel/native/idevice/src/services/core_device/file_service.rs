//! Browse and transfer files over the CoreDevice file service.

use std::borrow::Cow;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tracing::debug;

use crate::{IdeviceError, ReadWrite, RemoteXpcClient, obf, xpc::XPCObject};

use super::CoreDeviceError;

/// Fixed-size preamble the data port answers a `rwb!FILE` request with, before
/// the length-prefixed payload.
const DATA_PREAMBLE_LEN: usize = 0x24;
/// Maximum payload accepted before reserving memory for a download.
pub const FILE_SERVICE_MAX_READ_SIZE: usize = 128 * 1024 * 1024;
pub const FILE_SERVICE_CONTROL_TIMEOUT: Duration = Duration::from_secs(15);
pub const FILE_SERVICE_READ_TIMEOUT: Duration = Duration::from_secs(60);

/// Which of the device's filesystem domains a session is scoped to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Domain {
    /// An app's own data container. `identifier` is the bundle ID.
    AppDataContainer,
    /// A shared app-group container. `identifier` is the group ID.
    AppGroupDataContainer,
    /// The temporary directory.
    Temporary,
    /// The system crash-log store.
    SystemCrashLogs,
}

impl Domain {
    pub fn as_u64(self) -> u64 {
        match self {
            Domain::AppDataContainer => 1,
            Domain::AppGroupDataContainer => 2,
            Domain::Temporary => 3,
            Domain::SystemCrashLogs => 5,
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "appDataContainer" => Some(Domain::AppDataContainer),
            "appGroupDataContainer" => Some(Domain::AppGroupDataContainer),
            "temporary" => Some(Domain::Temporary),
            "systemCrashLogs" => Some(Domain::SystemCrashLogs),
            _ => None,
        }
    }
}

#[derive(Debug)]
pub struct FileServiceClient<R: ReadWrite> {
    inner: RemoteXpcClient<R>,
    session: Option<String>,
    usable: bool,
    control_timeout: Duration,
    read_timeout: Duration,
}

#[cfg(feature = "rsd")]
impl crate::RsdService for FileServiceClient<Box<dyn ReadWrite>> {
    fn rsd_service_name() -> Cow<'static, str> {
        obf!("com.apple.coredevice.fileservice.control")
    }

    async fn from_stream(stream: Box<dyn ReadWrite>) -> Result<Self, IdeviceError> {
        Self::new(stream).await
    }
}

impl<R: ReadWrite> FileServiceClient<R> {
    pub async fn new(inner: R) -> Result<Self, IdeviceError> {
        Self::new_with_timeout(inner, FILE_SERVICE_CONTROL_TIMEOUT).await
    }

    async fn new_with_timeout(inner: R, timeout: Duration) -> Result<Self, IdeviceError> {
        let inner = tokio::time::timeout(timeout, async {
            let mut inner = RemoteXpcClient::new(inner).await?;
            inner.do_handshake().await?;
            Ok::<_, IdeviceError>(inner)
        }).await.map_err(|_| IdeviceError::Timeout)??;
        Ok(Self {
            inner,
            session: None,
            usable: true,
            control_timeout: FILE_SERVICE_CONTROL_TIMEOUT,
            read_timeout: FILE_SERVICE_READ_TIMEOUT,
        })
    }

    /// Opens a session on `domain`, which every later command is scoped to.
    ///
    /// `identifier` names the container for the container domains (a bundle ID
    /// or an app-group ID) and is ignored by the others, which take `""`.
    pub async fn create_session(
        &mut self,
        domain: Domain,
        identifier: &str,
    ) -> Result<String, IdeviceError> {
        let result = tokio::time::timeout(self.control_timeout,
            self.create_session_inner(domain, identifier)).await;
        self.finish_operation(result)
    }

    async fn create_session_inner(
        &mut self,
        domain: Domain,
        identifier: &str,
    ) -> Result<String, IdeviceError> {
        let res = self
            .send_receive(crate::xpc!({
                "Cmd": "CreateSession",
                "Domain": XPCObject::UInt64(domain.as_u64()),
                "Identifier": identifier,
                "Session": "",
                "User": "mobile"
            }))
            .await?;

        let session = res
            .as_dictionary()
            .and_then(|d| d.get("NewSessionID"))
            .and_then(|v| v.as_string())
            .ok_or(CoreDeviceError::MissingField("NewSessionID"))?
            .to_string();
        self.session = Some(session.clone());
        Ok(session)
    }

    /// Lists `path`, relative to the session's domain root.
    pub async fn retrieve_directory_list(
        &mut self,
        path: &str,
    ) -> Result<Vec<String>, IdeviceError> {
        self.session()?;
        let result = tokio::time::timeout(self.control_timeout,
            self.retrieve_directory_list_inner(path)).await;
        self.finish_operation(result)
    }

    async fn retrieve_directory_list_inner(
        &mut self,
        path: &str,
    ) -> Result<Vec<String>, IdeviceError> {
        let session = self.session()?;
        let res = self
            .send_receive(crate::xpc!({
                "Cmd": "RetrieveDirectoryList",
                "MessageUUID": uuid::Uuid::new_v4().to_string(),
                "Path": path,
                "SessionID": session
            }))
            .await?;

        let list = res
            .as_dictionary()
            .and_then(|d| d.get("FileList"))
            .and_then(|v| v.as_array())
            .ok_or(CoreDeviceError::MissingField("FileList"))?;
        Ok(list
            .iter()
            .filter_map(|x| x.as_string().map(str::to_string))
            .collect())
    }

    /// Downloads `path`, relative to the session's domain root.
    pub async fn retrieve_file<S, F, Fut>(
        &mut self,
        path: &str,
        connect_data: F,
    ) -> Result<Vec<u8>, IdeviceError>
    where
        S: ReadWrite,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<S, IdeviceError>>,
    {
        self.session()?;
        let result = tokio::time::timeout(self.read_timeout,
            self.retrieve_file_inner(path, connect_data)).await;
        let result = self.finish_operation(result);
        if result.is_err() { self.invalidate_connection(); }
        result
    }

    async fn retrieve_file_inner<S, F, Fut>(
        &mut self,
        path: &str,
        connect_data: F,
    ) -> Result<Vec<u8>, IdeviceError>
    where
        S: ReadWrite,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<S, IdeviceError>>,
    {
        let session = self.session()?;
        let res = self
            .send_receive(crate::xpc!({
                "Cmd": "RetrieveFile",
                "Path": path,
                "SessionID": session
            }))
            .await?;
        let res = res
            .as_dictionary()
            .ok_or(CoreDeviceError::MalformedField("(root)"))?;

        let response = res
            .get("Response")
            .and_then(plist_u64)
            .ok_or(CoreDeviceError::MissingField("Response"))?;
        let file_id = res
            .get("NewFileID")
            .and_then(plist_u64)
            .ok_or(CoreDeviceError::MissingField("NewFileID"))?;

        let mut data_stream = connect_data().await?;

        // `rwb!FILE` then four big-endian u64s: the control reply's Response,
        // zero, the file ID it handed out, zero.
        let mut req = Vec::with_capacity(8 + 32);
        req.extend_from_slice(b"rwb!FILE");
        req.extend_from_slice(&response.to_be_bytes());
        req.extend_from_slice(&0u64.to_be_bytes());
        req.extend_from_slice(&file_id.to_be_bytes());
        req.extend_from_slice(&0u64.to_be_bytes());
        data_stream.write_all(&req).await?;
        data_stream.flush().await?;

        let mut preamble = [0u8; DATA_PREAMBLE_LEN];
        data_stream.read_exact(&mut preamble).await?;

        let mut len = [0u8; 4];
        data_stream.read_exact(&mut len).await?;
        let length = u32::from_be_bytes(len) as usize;
        if length > FILE_SERVICE_MAX_READ_SIZE {
            return Err(IdeviceError::UnexpectedResponse(
                "FileService payload exceeds the 128 MiB read limit".into(),
            ));
        }
        let mut payload = Vec::new();
        payload.try_reserve_exact(length).map_err(|_| {
            IdeviceError::InternalError("FileService payload allocation failed".into())
        })?;
        payload.resize(length, 0);
        data_stream.read_exact(&mut payload).await?;
        Ok(payload)
    }

    /// Creates an empty file at `path`, relative to the session's domain root.
    pub async fn propose_empty_file(
        &mut self,
        path: &str,
        file_permissions: u32,
        uid: u32,
        gid: u32,
        creation_time: i64,
        last_modification_time: i64,
    ) -> Result<(), IdeviceError> {
        let session = self.session()?;
        self.send_receive(crate::xpc!({
            "Cmd": "ProposeEmptyFile",
            "FileCreationTime": XPCObject::Int64(creation_time),
            "FileLastModificationTime": XPCObject::Int64(last_modification_time),
            "FilePermissions": XPCObject::Int64(file_permissions as i64),
            "FileOwnerUserID": XPCObject::Int64(uid as i64),
            "FileOwnerGroupID": XPCObject::Int64(gid as i64),
            "Path": path,
            "SessionID": session
        }))
        .await?;
        Ok(())
    }

    /// The session ID from the last [`create_session`](Self::create_session).
    pub fn session_id(&self) -> Option<&str> {
        self.session.as_deref()
    }

    /// A timed-out request may have partially sent or consumed protocol bytes.
    /// Prevent reuse rather than matching a late reply to a later request.
    pub fn invalidate_connection(&mut self) {
        self.usable = false;
        self.session = None;
    }

    fn finish_operation<T>(
        &mut self,
        result: Result<Result<T, IdeviceError>, tokio::time::error::Elapsed>,
    ) -> Result<T, IdeviceError> {
        match result {
            Err(_) => {
                self.invalidate_connection();
                Err(IdeviceError::Timeout)
            }
            Ok(Err(error @ IdeviceError::CoreDevice(CoreDeviceError::DeviceError(_)))) => Err(error),
            Ok(Err(error)) => {
                self.invalidate_connection();
                Err(error)
            }
            Ok(result) => result,
        }
    }

    fn session(&self) -> Result<String, IdeviceError> {
        if !self.usable { return Err(IdeviceError::NoEstablishedConnection); }
        self.session.clone().ok_or_else(|| {
            IdeviceError::UnexpectedResponse("no file service session; call create_session".into())
        })
    }

    async fn send_receive(
        &mut self,
        request: impl Into<XPCObject>,
    ) -> Result<plist::Value, IdeviceError> {
        if !self.usable {
            return Err(IdeviceError::NoEstablishedConnection);
        }
        self.inner.send_object(request, true).await?;
        // `CreateSession` is answered on the reply channel, every later command
        // on the root channel, so wait on both.
        let res = self.inner.recv_any().await?;
        debug!("file service reply: {res:?}");

        if let Some(dict) = res.as_dictionary()
            && dict.contains_key("EncodedError")
        {
            let detail = dict
                .get("LocalizedDescription")
                .and_then(|v| v.as_string())
                .map(str::to_string)
                .unwrap_or_else(|| format!("{:?}", dict.get("EncodedError")));
            return Err(CoreDeviceError::DeviceError(detail).into());
        }
        Ok(res)
    }
}

fn plist_u64(value: &plist::Value) -> Option<u64> {
    value
        .as_unsigned_integer()
        .or_else(|| value.as_signed_integer().map(|x| x as u64))
}

#[cfg(test)]
mod safety_tests {
    use super::*;
    use std::pin::Pin;
    use std::sync::{Arc, Mutex, atomic::{AtomicBool, AtomicUsize, Ordering}};
    use std::task::{Context, Poll};
    use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
    use crate::xpc::XPCMessage;

    #[derive(Debug)]
    struct MockStream {
        incoming: Vec<u8>,
        position: usize,
        eof: bool,
        stall_write: bool,
        written: Arc<Mutex<Vec<u8>>>,
        consumed: Arc<AtomicUsize>,
        dropped: Arc<AtomicUsize>,
    }

    impl MockStream {
        fn new(incoming: Vec<u8>, eof: bool) -> Self {
            Self { incoming, position: 0, eof, stall_write: false,
                written: Arc::new(Mutex::new(Vec::new())),
                consumed: Arc::new(AtomicUsize::new(0)),
                dropped: Arc::new(AtomicUsize::new(0)) }
        }
    }
    impl Drop for MockStream {
        fn drop(&mut self) { self.dropped.fetch_add(1, Ordering::SeqCst); }
    }
    impl AsyncRead for MockStream {
        fn poll_read(mut self: Pin<&mut Self>, _cx: &mut Context<'_>, buf: &mut ReadBuf<'_>)
            -> Poll<std::io::Result<()>> {
            if self.position == self.incoming.len() {
                return if self.eof { Poll::Ready(Ok(())) } else { Poll::Pending };
            }
            // Force fragmentation through both HTTP/2 control and data framing.
            let count = (self.incoming.len() - self.position).min(buf.remaining()).min(3);
            buf.put_slice(&self.incoming[self.position..self.position + count]);
            self.position += count;
            self.consumed.store(self.position, Ordering::SeqCst);
            Poll::Ready(Ok(()))
        }
    }
    impl AsyncWrite for MockStream {
        fn poll_write(self: Pin<&mut Self>, _cx: &mut Context<'_>, buf: &[u8])
            -> Poll<std::io::Result<usize>> {
            if self.stall_write { return Poll::Pending; }
            let count = buf.len().min(5);
            self.written.lock().unwrap().extend_from_slice(&buf[..count]);
            Poll::Ready(Ok(count))
        }
        fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>)
            -> Poll<std::io::Result<()>> { Poll::Ready(Ok(())) }
        fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>)
            -> Poll<std::io::Result<()>> { Poll::Ready(Ok(())) }
    }

    fn response(channel: u32, object: XPCObject) -> Vec<u8> {
        let body = XPCMessage::new(None, Some(object), Some(1)).encode(1).unwrap();
        let length = (body.len() as u32).to_be_bytes();
        let mut frame = vec![length[1], length[2], length[3], 0, 0];
        frame.extend(channel.to_be_bytes());
        frame.extend(body);
        frame
    }
    fn session_response() -> Vec<u8> {
        response(3, crate::xpc!({ "NewSessionID": "mock-session" }))
    }
    fn file_response() -> Vec<u8> {
        response(1, crate::xpc!({ "Response": 7u64, "NewFileID": 19u64 }))
    }
    fn data_reply(length: u32, bytes: &[u8]) -> Vec<u8> {
        let mut reply = vec![0; DATA_PREAMBLE_LEN];
        reply.extend(length.to_be_bytes());
        reply.extend(bytes);
        reply
    }
    fn control_commands(bytes: &[u8]) -> Vec<plist::Dictionary> {
        assert_eq!(&bytes[..24], b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n");
        let mut offset = 24;
        let mut commands = Vec::new();
        while offset < bytes.len() {
            let header = &bytes[offset..offset + 9];
            let length = u32::from_be_bytes([0, header[0], header[1], header[2]]) as usize;
            let body = &bytes[offset + 9..offset + 9 + length];
            if header[3] == 0 {
                let message = XPCMessage::decode(body).unwrap();
                if let Some(value) = message.message {
                    let value = value.to_plist();
                    if let Some(dict) = value.as_dictionary() && dict.contains_key("Cmd") {
                        commands.push(dict.clone());
                    }
                }
            }
            offset += 9 + length;
        }
        commands
    }
    async fn session_client(extra: Vec<u8>) -> FileServiceClient<MockStream> {
        let mut replies = session_response();
        replies.extend(extra);
        let mut client = FileServiceClient::new(MockStream::new(replies, false)).await.unwrap();
        client.create_session(Domain::AppDataContainer, "test.owned.app").await.unwrap();
        client
    }

    #[tokio::test]
    async fn fragmented_control_and_binary_download_preserve_wire_protocol() {
        let mut replies = session_response();
        replies.extend(response(1, crate::xpc!({ "FileList": ["Library/Caches/file", "Documents"] })));
        replies.extend(file_response());
        let control = MockStream::new(replies, false);
        let control_written = control.written.clone();
        let mut client = FileServiceClient::new(control).await.unwrap();
        assert_eq!(client.create_session(Domain::AppDataContainer, "test.owned.app").await.unwrap(), "mock-session");
        assert_eq!(client.retrieve_directory_list(".").await.unwrap(), vec!["Library/Caches/file", "Documents"]);
        let expected = [0, 0xff, 0x80, b'P', b'K', 0, 0xfe];
        let data = MockStream::new(data_reply(expected.len() as u32, &expected), true);
        let written = data.written.clone();
        let dropped = data.dropped.clone();
        let actual = client.retrieve_file("Documents/file", async || Ok(data)).await.unwrap();
        assert_eq!(actual, expected);
        assert_eq!(dropped.load(Ordering::SeqCst), 1);
        let mut request = b"rwb!FILE".to_vec();
        for value in [7u64, 0, 19, 0] { request.extend(value.to_be_bytes()); }
        assert_eq!(*written.lock().unwrap(), request);
        let commands = control_commands(&control_written.lock().unwrap());
        assert_eq!(commands.len(), 3);
        assert_eq!(commands[0]["Cmd"].as_string(), Some("CreateSession"));
        assert_eq!(commands[0]["Domain"].as_unsigned_integer(), Some(1));
        assert_eq!(commands[0]["Identifier"].as_string(), Some("test.owned.app"));
        assert_eq!(commands[0]["User"].as_string(), Some("mobile"));
        assert_eq!(commands[1]["Cmd"].as_string(), Some("RetrieveDirectoryList"));
        assert_eq!(commands[1]["Path"].as_string(), Some("."));
        assert!(uuid::Uuid::parse_str(commands[1]["MessageUUID"].as_string().unwrap()).is_ok());
        assert_eq!(commands[2]["Cmd"].as_string(), Some("RetrieveFile"));
        assert_eq!(commands[2]["Path"].as_string(), Some("Documents/file"));
        assert_eq!(commands[2]["SessionID"].as_string(), Some("mock-session"));
    }

    #[tokio::test]
    async fn oversized_length_is_rejected_before_any_payload_read() {
        for length in [(FILE_SERVICE_MAX_READ_SIZE + 1) as u32, u32::MAX] {
            let mut client = session_client(file_response()).await;
            let data = MockStream::new(data_reply(length, b"must-not-be-read"), false);
            let consumed = data.consumed.clone();
            let dropped = data.dropped.clone();
            let result = client.retrieve_file("known-file", async || Ok(data)).await;
            assert!(matches!(result, Err(IdeviceError::UnexpectedResponse(ref message)) if message.contains("128 MiB")));
            assert_eq!(consumed.load(Ordering::SeqCst), DATA_PREAMBLE_LEN + 4);
            assert_eq!(dropped.load(Ordering::SeqCst), 1);
            assert!(matches!(client.retrieve_directory_list(".").await, Err(IdeviceError::NoEstablishedConnection)));
        }
    }

    #[tokio::test]
    async fn empty_file_is_a_valid_zero_length_download() {
        let mut client = session_client(file_response()).await;
        let data = MockStream::new(data_reply(0, &[]), true);
        assert!(client.retrieve_file("empty", async || Ok(data)).await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn truncated_payload_closes_the_operation_without_partial_contents() {
        let mut client = session_client(file_response()).await;
        let data = MockStream::new(data_reply(4, &[0, 0xff]), true);
        let dropped = data.dropped.clone();
        let result = client.retrieve_file("truncated", async || Ok(data)).await;
        assert!(matches!(result, Err(IdeviceError::Socket(ref error)) if error.kind() == std::io::ErrorKind::UnexpectedEof));
        assert_eq!(dropped.load(Ordering::SeqCst), 1);
        assert!(!client.usable);
    }

    #[tokio::test]
    async fn stalled_constructor_is_cancelled_and_drops_its_stream() {
        let mut stream = MockStream::new(Vec::new(), false);
        stream.stall_write = true;
        let dropped = stream.dropped.clone();
        let result = FileServiceClient::new_with_timeout(stream, Duration::from_millis(30)).await;
        assert!(matches!(result, Err(IdeviceError::Timeout)));
        assert_eq!(dropped.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn stalled_session_cannot_be_reused_for_a_late_response() {
        let stream = MockStream::new(Vec::new(), false);
        let written = stream.written.clone();
        let mut client = FileServiceClient::new(stream).await.unwrap();
        client.control_timeout = Duration::from_millis(30);
        assert!(matches!(client.create_session(Domain::AppDataContainer, "test.owned.app").await, Err(IdeviceError::Timeout)));
        let before = written.lock().unwrap().len();
        assert!(matches!(client.create_session(Domain::AppDataContainer, "test.owned.app").await, Err(IdeviceError::NoEstablishedConnection)));
        assert_eq!(written.lock().unwrap().len(), before);
    }

    #[tokio::test]
    async fn incomplete_directory_control_frame_times_out_and_invalidates() {
        let mut client = session_client(vec![0, 0, 100, 0, 0, 0]).await;
        client.control_timeout = Duration::from_millis(30);
        assert!(matches!(client.retrieve_directory_list(".").await, Err(IdeviceError::Timeout)));
        assert!(!client.usable);
        assert!(client.session_id().is_none());
    }

    #[tokio::test]
    async fn download_deadline_covers_control_reply_before_data_connect() {
        let mut client = session_client(Vec::new()).await;
        client.read_timeout = Duration::from_millis(30);
        let connected = Arc::new(AtomicBool::new(false));
        let flag = connected.clone();
        let result = client.retrieve_file("silent-control", async move || {
            flag.store(true, Ordering::SeqCst);
            Ok(MockStream::new(Vec::new(), false))
        }).await;
        assert!(matches!(result, Err(IdeviceError::Timeout)));
        assert!(!connected.load(Ordering::SeqCst));
        assert!(!client.usable);
    }

    #[tokio::test]
    async fn download_deadline_covers_stalled_data_and_drops_stream() {
        let mut client = session_client(file_response()).await;
        client.read_timeout = Duration::from_millis(30);
        let data = MockStream::new(vec![0; 8], false);
        let dropped = data.dropped.clone();
        let result = client.retrieve_file("silent-data", async || Ok(data)).await;
        assert!(matches!(result, Err(IdeviceError::Timeout)));
        assert_eq!(dropped.load(Ordering::SeqCst), 1);
        assert!(!client.usable);
    }

    #[tokio::test]
    async fn device_session_denial_does_not_poison_a_complete_control_reply() {
        let mut replies = response(3, crate::xpc!({ "EncodedError": "permission", "LocalizedDescription": "denied" }));
        replies.extend(session_response());
        let mut client = FileServiceClient::new(MockStream::new(replies, false)).await.unwrap();
        assert!(client.create_session(Domain::AppDataContainer, "test.owned.app").await.is_err());
        assert!(client.usable);
        assert_eq!(client.create_session(Domain::AppDataContainer, "test.owned.app").await.unwrap(), "mock-session");
    }

    #[tokio::test]
    async fn malformed_complete_control_reply_invalidates_without_reuse() {
        let mut malformed = response(1, crate::xpc!({ "FileList": ["file"] }));
        malformed[9] ^= 0xff; // Corrupt the XPC wrapper magic, preserving HTTP/2 framing.
        let mut client = session_client(malformed).await;
        assert!(client.retrieve_directory_list(".").await.is_err());
        assert!(!client.usable);
        assert!(matches!(client.create_session(Domain::AppDataContainer, "test.owned.app").await, Err(IdeviceError::NoEstablishedConnection)));
    }

    #[tokio::test]
    async fn caller_without_session_can_still_open_a_valid_session() {
        let mut client = FileServiceClient::new(MockStream::new(session_response(), false)).await.unwrap();
        assert!(client.retrieve_directory_list(".").await.is_err());
        assert!(client.usable);
        assert_eq!(client.create_session(Domain::AppDataContainer, "test.owned.app").await.unwrap(), "mock-session");
    }
}
