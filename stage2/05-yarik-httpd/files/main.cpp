// yarik-os demo web server.
//
// A tiny, dependency-free HTTP/1.1 server. It answers every GET request to "/"
// with the body "It is yarik-os!" and listens on 0.0.0.0:1337. Anything else
// gets a 404 (wrong path) or 405 (wrong method).
//
// Kept deliberately small and built as a fully static binary so it can be
// dropped straight into the Buildroot root filesystem regardless of the target
// libc.

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <string>

namespace {

constexpr int kPort = 1337;
constexpr char kBody[] = "It is yarik-os!\n";

std::string BuildResponse(int status, const char* reason, const std::string& body) {
  std::string r = "HTTP/1.1 " + std::to_string(status) + " " + reason + "\r\n";
  r += "Content-Type: text/plain\r\n";
  r += "Content-Length: " + std::to_string(body.size()) + "\r\n";
  r += "Connection: close\r\n\r\n";
  r += body;
  return r;
}

void HandleClient(int fd) {
  char buf[4096];
  ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
  if (n <= 0) {
    close(fd);
    return;
  }
  buf[n] = '\0';

  // Parse the request line: "METHOD PATH VERSION".
  char method[16] = {0};
  char path[1024] = {0};
  std::sscanf(buf, "%15s %1023s", method, path);

  // Drop any query string so "/?foo=bar" still matches "/".
  std::string p(path);
  const auto q = p.find('?');
  if (q != std::string::npos) p.resize(q);

  std::string response;
  if (std::strcmp(method, "GET") == 0 && p == "/") {
    response = BuildResponse(200, "OK", kBody);
  } else if (std::strcmp(method, "GET") != 0) {
    response = BuildResponse(405, "Method Not Allowed", "Method Not Allowed\n");
  } else {
    response = BuildResponse(404, "Not Found", "Not Found\n");
  }

  // Best-effort full send.
  size_t off = 0;
  while (off < response.size()) {
    ssize_t w = send(fd, response.data() + off, response.size() - off, 0);
    if (w <= 0) break;
    off += static_cast<size_t>(w);
  }
  close(fd);
}

}  // namespace

int main() {
  // A peer hanging up mid-write must not kill the server.
  std::signal(SIGPIPE, SIG_IGN);

  const int srv = socket(AF_INET, SOCK_STREAM, 0);
  if (srv < 0) {
    std::perror("socket");
    return 1;
  }

  int one = 1;
  setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(kPort);

  if (bind(srv, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    std::perror("bind");
    return 1;
  }
  if (listen(srv, 16) < 0) {
    std::perror("listen");
    return 1;
  }

  std::printf("yarik-os web server listening on 0.0.0.0:%d\n", kPort);
  std::fflush(stdout);

  for (;;) {
    const int cli = accept(srv, nullptr, nullptr);
    if (cli < 0) {
      if (errno == EINTR) continue;
      std::perror("accept");
      continue;
    }
    HandleClient(cli);
  }

  return 0;  // unreachable
}
