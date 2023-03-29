import { serve } from "https://deno.land/std@0.181.0/http/server.ts";
import { Bot, webhookCallback } from "https://deno.land/x/grammy@v1.15.3/mod.ts";
// Puedes modificar esto a la forma correcta de importar tu objeto `Bot`.
import bot from ./fenite.pl;

const handleUpdate = webhookCallback(bot, "std/http");

serve(async (req) => {
  if (req.method === "POST") {
    const url = new URL(req.url);
    if (url.pathname.slice(1) === bot.token) {
      try {
        return await handleUpdate(req);
      } catch (err) {
        console.error(err);
      }
    }
  }
  return new Response();
});
