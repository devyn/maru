var event_source;

var tasks = {};

var selected_task_id = null
  , created_task_id  = null;

var popup_window_transition_duration = 200; // msecs

function template(name, argument) {
  var template_element = $("template#" + name + "_template");

  if (template_element.hasClass('handlebars')) {
    return $.parseHTML(template.handlebars[name + "_template"](argument));
  } else {
    return template_element[0].content.cloneNode(true);
  }
}
template.handlebars = {}; // handlebars compiled template cache

function ease_in(el) {
  $(el).css({
    transition: "opacity ease 0.5s, height ease 0.5s, padding ease 0.5s",
    height:     0,
    padding:    0,
    opacity:    0
  });

  setTimeout(function () {
    $(el).css({
      height:  "",
      padding: "",
      opacity: 1
    });

    setTimeout(function () {
      $(el).css({
        transition: "",
        opacity: ""
      });
    }, 500);
  }, 0);
}

function ease_out(el, callback) {
  $(el).css({
    transition: "opacity ease 0.5s, height ease 0.5s, padding ease 0.5s",
    height:     "",
    padding:    "",
    opacity:    1
  });

  setTimeout(function () {
    $(el).css({
      height:  0,
      padding: 0,
      opacity: 0
    });

    setTimeout(function () {
      if (typeof callback === 'function')
        callback(el);
    }, 500);
  }, 0);
}

function create_task_element(task) {
  task.element = template("task_element", task)[1];

  update_progress(task);
  update_task_speed(task);

  $(task.element).click(function () {
    select_task(task);
  });

  // next tick to avoid the transition
  setTimeout(function () {
    $("#tasks").prepend(task.element);
  }, 0);
}

function update_task_speed(task) {
  var nearest_job  = task.recent_jobs[0]
    , farthest_job = task.recent_jobs[task.recent_jobs.length - 1];

  if (nearest_job && farthest_job) {
    var nearest_time     = Date.parse(nearest_job.submitted_at)
      , farthest_time    = Date.parse(farthest_job.submitted_at);

    if (nearest_time === farthest_time) {

      $(".task_speed", task.element).empty();
    } else {

      var average_duration = (nearest_time - farthest_time) / task.recent_jobs.length
        , speed            = (1000 / average_duration) * 60 * 60;

      if (Date.now() > nearest_time + average_duration * 2) {
        // If double the average duration of a job has passed,
        // the job should be considered inactive.
        $(".task_speed", task.element).empty();
      } else {
        $(".task_speed", task.element).text(speed.toFixed(2) + " jobs/h");
      }
    }
  } else {
    $(".task_speed", task.element).empty();
  }
}

function update_progress(task) {
  if (task.total_jobs !== null) {
    var percent = task.submitted_jobs / task.total_jobs * 100;

    setTimeout(function () {
      $('.progress_fill', task.element).css('width', percent.toString() + "%");
    }, 10);

    $('.progress_text', task.element).text( 
        "" + task.submitted_jobs + "/" + task.total_jobs +
          " completed (" + percent.toFixed(2) + "%)");
  } else {
    $('.progress_text', task.element).text(
        "" + task.submitted_jobs + " completed");
  }
}

function select_task(task) {
  if (selected_task_id !== task.id) {
    if (selected_task_id !== null) {
      $(tasks[selected_task_id].element).removeClass('selected');
    }

    selected_task_id = task.id;

    $(task.element).addClass('selected');
  } else {
    $(task.element).removeClass('selected');

    selected_task_id = null;
  }

  show_details();
}

function task_secret_info(task_id) {
  if (localStorage["task_secret_info:" + task_id]) {
    return JSON.parse(localStorage["task_secret_info:" + task_id]);
  }
}

function show_details() {
  $("#details").empty();

  if (selected_task_id !== null) {
    var task = tasks[selected_task_id];

    task.secret_info = task_secret_info(selected_task_id);

    $("#details").html(template("task_details", task));

    $("#details .task_produce_link").click(task_produce_link);

    for (var i = task.recent_jobs.length - 1; i >= 0; i--) {
      var job = task.recent_jobs[i];

      prepend_job_element(job);
    }
  }
}

function prepend_job_element(job) {
  var type = job.type ? job.type.split(".") : [];

  if (type.length > 1) {
    job.type_namespace = type.slice(0, type.length - 1).join(".") + ".";
    job.type_subname   = type[type.length - 1];
  }

  var job_element = template("task_job", job)[1];

  $("#jobs").prepend(job_element);
  return job_element;
}

function tasks_reload(e) {
  var data = JSON.parse(e.data);

  $("#tasks").empty();

  tasks = {};

  for (var i = 0; i < data.length; i++) {
    var task = tasks[data[i].id] = {};

    task.id   = data[i].id;
    task.name = data[i].name;

    task.total_jobs     = data[i].total_jobs;
    task.submitted_jobs = data[i].submitted_jobs;
    task.recent_jobs    = data[i].recent_jobs;

    create_task_element(task);

    if (selected_task_id === task.id) {
      $(task.element).addClass("selected");
    }
  }

  if (!tasks.hasOwnProperty(selected_task_id)) {
    selected_task_id = null;
  }

  show_details();
}

function tasks_taskcreated(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.id] = {};

  task.id   = data.id;
  task.name = data.name;

  task.total_jobs     = data.total_jobs;
  task.submitted_jobs = 0;
  task.recent_jobs    = [];

  create_task_element(task);

  if (created_task_id === task.id) {
    console.log(['created_task_id', task.id]);
    setTimeout(function () {
      select_task(task);
    }, 0);
  }
}

function tasks_jobsubmitted(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.task_id];

  delete data.task_id;

  // reorder
  $("#tasks").prepend(task.element);

  task.submitted_jobs++;

  if (task.recent_jobs.length >= 10) {
    task.recent_jobs.pop();

    if (selected_task_id === task.id) {
      ease_out($("#jobs")[0].children[9], function (el) {
        el.remove();
      });
    }
  }

  task.recent_jobs.unshift(data);

  update_task_speed(task);

  if (selected_task_id === task.id) {
    var job_el = prepend_job_element(data);

    ease_in(job_el);
  }

  $(task.element).addClass("flash");

  update_progress(task);

  setTimeout(function () {
    $(task.element).removeClass("flash");
  }, 0);
}

function tasks_changetotal(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.task_id];

  task.total_jobs = data.total_jobs;

  update_progress(task);
}

function init_new_task() {
  $("#new_task .create_button").click(function (e) {
    $.post('/tasks', $("#new_task form").serialize(), function (response) {
      localStorage["task_secret_info:" + response.id] = JSON.stringify(response);

      if (tasks.hasOwnProperty(response.id)) {
        select_task(tasks[response.id]);
      } else {
        created_task_id = response.id;
      }

      $("#click_catcher, #new_task").removeClass("show");
      setTimeout(function () {
        $("#click_catcher").css({display: ''})
        $("#new_task").remove();
      }, popup_window_transition_duration);
    });
  });

  $("#new_task select[name='producer']").change(function (e) {
    if ($(this).val() === '') {

      $("#new_task .setup .if_empty")    .show();
      $("#new_task .setup .if_not_empty").hide();
    } else {

      $("#new_task .setup .if_empty")    .hide();
      $("#new_task .setup .if_not_empty").show();
    }
  });

  $("#new_task .configure_button").click(function (e) {
    $.get("/producer/" +
      $("#new_task select[name='producer']").val() + "/form",

      function (form) {

        $("#new_task .configure .producer_form").html(form);
        $("#new_task .configure").show();
        $("#new_task .setup").hide();
      });
  });
}

function task_produce_link(e) {
  $(".popup_window").remove();

  $("body").append(template("task_produce"));
  init_task_produce();

  $("#click_catcher, #task_produce").css({display: 'block'});

  setTimeout(function () {
    $("#click_catcher, #task_produce").addClass("show");
  }, 0);

  e.stopPropagation();
}

function init_task_produce() {
  $("#task_produce .produce_button").click(function (e) {
    $.post('/task/' + task_secret_info(selected_task_id).secret + '/produce',
      $("#task_produce form").serialize(),

      function (response) {
        $("#click_catcher, #task_produce").removeClass("show");
        setTimeout(function () {
          $("#click_catcher").css({display: ''})
          $("#task_produce").remove();
        }, popup_window_transition_duration);
      });
  });

  $("#task_produce select[name='producer']").change(function (e) {
    if ($(this).val() === '') {

      $("#task_produce .configure_button").prop('disabled', true);
    } else {

      $("#task_produce .configure_button").prop('disabled', false);
    }
  });

  $("#task_produce .configure_button").click(function (e) {
    $.get("/producer/" +
      $("#task_produce select[name='producer']").val() + "/form",

      function (form) {

        $("#task_produce .configure .producer_form").html(form);
        $("#task_produce .configure").show();
        $("#task_produce .setup").hide();
      });
  });
}

$(function() {
  // compile templates
  $("template.handlebars").each(function() {
    template.handlebars[this.id] = Handlebars.compile($(this).html());
  });

  // establish event source
  event_source = new EventSource("/tasks.event-stream");

  event_source.addEventListener("reload",       tasks_reload);
  event_source.addEventListener("taskcreated",  tasks_taskcreated);
  event_source.addEventListener("jobsubmitted", tasks_jobsubmitted);
  event_source.addEventListener("changetotal",  tasks_changetotal);

  // register actions
  $("#click_catcher").click(function() {
    $("#click_catcher, .popup_window").removeClass("show");
    setTimeout(function () {
      $("#click_catcher").css({display: ''});
      $(".popup_window").remove();
    }, popup_window_transition_duration);
  });
  $(".popup_window").click(function (e) {
    e.stopPropagation();
  });

  $("#new_task_link").click(function (e) {
    $(".popup_window").remove();

    $("body").append(template("new_task"));
    init_new_task();

    $("#click_catcher, #new_task").css({display: 'block'});

    setTimeout(function () {
      $("#click_catcher, #new_task").addClass("show");
    }, 0);

    e.stopPropagation();
  });

});
