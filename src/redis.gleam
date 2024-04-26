import gleam/bit_array
import gleam/bytes_builder
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/regex
import gleam/result
import gleam/string
import glisten

pub fn main() {
  io.println("Logs from your program will appear here!")

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(Nil, None) }, handle_redis_command)
    |> glisten.serve(6379)

  process.sleep_forever()
}

fn handle_redis_command(msg, state, conn) {
  let assert glisten.Packet(msg) = msg

  let tokens = tokenize(msg)
  io.debug(tokens)

  let result = case tokens {
    ["ping", ..] -> "+PONG\r\n"
    ["echo", to_echo, ..] ->
      "$"
      <> int.to_string(string.length(to_echo))
      <> "\r\n"
      <> to_echo
      <> "\r\n"
    [_, ..] -> "-ERR unknown command\r\n"
    [] -> "-ERR empty command\r\n"
  }

  let assert Ok(_) = glisten.send(conn, bytes_builder.from_string(result))
  actor.continue(state)
}

fn tokenize(msg) {
  bit_array.to_string(msg)
  |> result.map(string.split(_, on: "\r\n"))
  |> result.unwrap([])
  |> list.filter(fn(s) { !is_special(s) && !string.is_empty(s) })
}

fn is_special(s) {
  regex.from_string("^[*$]\\d$")
  |> result.map(regex.check(_, s))
  |> result.unwrap(False)
}
