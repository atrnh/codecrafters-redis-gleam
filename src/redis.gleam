import gleam/bit_array
import gleam/bytes_builder
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/regex
import gleam/result
import gleam/string
import glisten

pub fn main() {
  io.println("Logs from your program will appear here!")

  let assert Ok(_) =
    glisten.handler(
      fn(_conn) { #(dict.new(), None) },
      fn(cmd, state: Dict(String, String), conn) {
        let assert glisten.Packet(cmd) = cmd
        let state = handle_redis_command(cmd, state, conn)
        actor.continue(state)
      },
    )
    |> glisten.serve(6379)

  process.sleep_forever()
}

fn handle_redis_command(cmd, state: Dict(String, String), conn) {
  let tokens = tokenize(cmd)
  case tokens {
    ["PING", ..] -> {
      let assert Ok(_) = create_simple_string("PONG") |> send_response(conn)
      state
    }
    ["ECHO", to_echo, ..] -> {
      let assert Ok(_) =
        Some(to_echo) |> create_bulk_string |> send_response(conn)
      state
    }
    ["SET", key, val, ..] -> {
      let assert Ok(_) = create_simple_string("OK") |> send_response(conn)
      state |> dict.insert(key, val)
    }
    ["GET", key, ..] -> {
      let assert Ok(_) =
        state
        |> dict.get(key)
        |> option.from_result
        |> create_bulk_string
        |> send_response(conn)
      state
    }
    [_, ..] -> {
      let assert Ok(_) =
        create_error_string("ERR unknown command") |> send_response(conn)
      state
    }
    [] -> {
      let assert Ok(_) =
        create_error_string("ERR empty command") |> send_response(conn)
      state
    }
  }
}

fn send_response(response, conn) {
  glisten.send(conn, bytes_builder.from_string(response))
}

fn create_bulk_string(data: Option(String)) -> String {
  case data {
    Some(s) -> "$" <> int.to_string(string.length(s)) <> "\r\n" <> s <> "\r\n"
    None -> "$-1\r\n"
  }
}

fn create_simple_string(data: String) -> String {
  "+" <> data <> "\r\n"
}

fn create_error_string(error_msg: String) -> String {
  "-" <> error_msg <> "\r\n"
}

fn tokenize(tokens) {
  bit_array.to_string(tokens)
  |> result.map(string.split(_, on: "\r\n"))
  |> result.unwrap([])
  |> list.filter(fn(s) { !is_special(s) && !string.is_empty(s) })
}

fn is_special(s: String) {
  regex.from_string("^[*$]\\d$")
  |> result.map(regex.check(_, s))
  |> result.unwrap(False)
}
