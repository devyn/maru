# maru

maru (丸; circle) is a computational task distribution system designed with sharing in mind.

maru masters can employ many workers, and maru workers can subscribe to many masters.
This allows for the creation of large, distributed networks of masters and workers in
which there is no single point of control, and work can be shared freely.

It is intended as a means of distributed computing through collaboration.

## Installation

### Master

    $ git clone https://github.com/devyn/maru.git
    $ cd maru
    $ bundle install 
    $ cp config.ru{.example,}
    $ "$EDITOR" config.ru

Proceed to edit the `config.ru` according to the comments. At the minimum, you should change
the secret and install a filestore. You also likely want to require some plugins.

If `ENV["DATABASE_URL"]` is set before requiring `maru/master`, it will be fed to DataMapper.
You likely want to change this, as sqlite3 (the default) is rather slow.

Likewise, if `ENV["RACK_ENV"]` is set, that environment will be used. You probably only need to
change this if you intend on developing plugins for maru or working on maru itself.

Finally, `Maru::Log.log_level` can be set to one of `"DEBUG"`, `"INFO"`, `"WARN"`, `"ERROR"`,
or `"CRITICAL"`. `"WARN"` is recommended if `"INFO"`, the default, seems too verbose.

The master must be run on an EventMachine-based server. Thin is recommended and included in the
bundle.

    $ bundle exec thin start -p <PORT> # [-d] to daemonize

### Worker

    $ git clone https://github.com/devyn/maru.git
    $ cd maru
    $ bundle install
    $ bundle exec bin/maru-worker --config-example > worker.yaml

Proceed to edit the `worker.yaml` using the following reference:

<dl>
<dt>name</dt>
<dd>
  Required. The name of the worker. Must be unique across all registered masters.
</dd>
<dt>masters</dt>
<dd>
  A list of <code>{url,key}</code> objects. For example:

<pre>
masters:
- url: https://compute.example.com/
  key: t912jpgz9tm40drqqr73lhrh
- url: https://alice.example.org/maru/
  key: ck29my3ivkstit7tno7kzijf
</pre>
</dd>
<dt>plugins</dt>
<dd>
  A list of paths to plugin files to load. It is recommended that these be absolute paths.
</dd>
<dt>wait_time</dt>
<dd>
  Duration in seconds to wait before retrying all known masters if no jobs were found.
  Default: 60.
</dd>
<dt>group_expiry</dt>
<dd>
  Length of time in seconds after the last recorded activity until a group's cached data expires.
  Default: 3600.
</dd>
<dt>log_level</dt>
<dd>
  Sets the minimum log level. Acceptable values: <code>DEBUG</code>, <code>INFO</code>,
  <code>WARN</code>, <code>ERROR</code>, <code>CRITICAL</code>.
  Default: <code>INFO</code>.
</dd>
<dt>temp_dir</dt>
<dd>
  Directory in which to keep temporary files, like the group cache.
  Default: <code>/tmp/maru.&lt;PID&gt;</code>.
</dd>
<dt>keep_temp</dt>
<dd>
  Boolean; whether to keep temporary files after the worker process has exited.
  Default: <code>false</code>.
</dd>
</dl>

You may wish to keep separate configurations for each worker. Note that workers are by design
single-threaded; plugins should ensure they do not do work in parallel. Therefore it is
recommended to start one worker per core.

Assuming you now have a `worker.yaml` ready, simply:

    $ bundle exec bin/maru-worker -c worker.yaml

and watch your newly minted worker run jobs.

## Bugs

Please report them [here](https://github.com/devyn/maru/issues/).

## License

Copyright (c) 2012, Devyn Cairns
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of maru nor the
  names of its contributors may be used to endorse or promote products
  derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Devyn Cairns BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

