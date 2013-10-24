var event_source;

var tasks = {};

var selected_task_id = null
  , created_task_id  = null;

var popup_window_transition_duration = 200; // msecs

var maru_default_port = 8490;

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

// Kind of a hack to change an element without invoking its CSS transitions.
function change_without_transition(element, procedure) {
  $(element).addClass('notransition');

  procedure(element);

  setTimeout(function () {
    $(element).removeClass('notransition');
  }, 100);
}

function create_task_element(task) {
  task.element = template("task_element", task)[0];

  change_without_transition($(".progress_fill", task.element),
      function () { update_progress(task); });

  update_task_speed(task);

  $(task.element).click(function () {
    select_task(task);
  });

  $("#tasks").prepend(task.element);
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

function show_details() {
  $("#details").empty();

  if (selected_task_id !== null) {
    var task = tasks[selected_task_id];

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

  var job_element = template("task_job", job)[0];

  $("#jobs").prepend(job_element);
  return job_element;
}

// needs DRY with tasks_taskcreated
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

    task.relationship_to_user = data[i].relationship_to_user;
    task.secret               = data[i].secret;
    task.submit_to            = data[i].submit_to;

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

// needs DRY with tasks_reload
function tasks_taskcreated(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.id] = {};

  task.id   = data.id;
  task.name = data.name;

  task.total_jobs     = data.total_jobs;
  task.submitted_jobs = 0;
  task.recent_jobs    = [];

  task.relationship_to_user = data.relationship_to_user;
  task.secret               = data.secret;
  task.submit_to            = data.submit_to;

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

function post_change_user(user_info) {
  window.user_info = user_info;

  update_nav(user_info);

  // Reconnect to the task event stream in order to get the tasks
  // for this user.
  connect_to_task_event_stream();
}

var default_network_port = 8490;

function update_clients() {
  if (window.user_info) {
    $.ajax({
        url: '/user/' + window.user_info.name + '/clients',
        dataType: 'json',
        success: function (clients) {
          $("select.networks").html("<option value='' selected>-</option>");

          $.each(clients, function (i, client) {
            if (client.is_producer) {
              $("select.networks").append(
                $("<option />").attr("value", client.id)
                               .text(client.remote_host +
                                     (client.remote_port === default_network_port ? "" : ":" + client.remote_port) +
                                     " (as " + client.name + ")"));
            }
          });
        }
    });
  }
}

var popup_windows = {
  user_login: {
    template_name: "user_login",
    initialize: function () {
      $("#user_login form").submit(function (e) {
        e.preventDefault();

        $.ajax({
          type: "POST",
          url: "/user/" + encodeURIComponent($("#user_login form input[name='username']").val()) + "/login",
          data: {
            password: $("#user_login form input[name='password']").val()
          },
          dataType: "json",
          success: function (data) {
            post_change_user(data.user);
            close_popup_window();
          },
          error: function (xhr) {
            if (xhr.statusCode() == 403) {
              popup_window_error_message("Wrong username or password");
            }
          }
        });
      });

      setTimeout(function () {
        $("#user_login form input:first").focus();
      }, 0);
    }
  },

  new_task: {
    template_name: "new_task",
    initialize: function () {
      $("#new_task .create_button").click(function (e) {
        $.post('/tasks', $("#new_task form").serialize(), function (response) {
          if (tasks.hasOwnProperty(response.id)) {
            select_task(tasks[response.id]);
          } else {
            created_task_id = response.id;
          }

          close_popup_window();
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

      update_clients();
    }
  },

  task_produce: {
    template_name: "task_produce",
    initialize: function () {
      $("#task_produce .produce_button").click(function (e) {
        $.post('/task/' + selected_task_id + '/produce',
          $("#task_produce form").serialize(),

          function (response) {
            close_popup_window();
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

      update_clients();
    }
  },

  user_clients: {
    template_name: "user_clients",
    initialize: function () {
      $.ajax({
        url: '/user/' + encodeURIComponent(window.user_info.name) + '/clients',
        dataType: 'json',
        success: function (clients) {
          var locations = {}, locations_order = [];

          $.each(clients, function (i, client) {
            var location_string = client.remote_host;

            // Only include the port number if it's non-standard
            if (client.remote_port !== maru_default_port)
              location_string += ":" + client.remote_port;

            if (!locations[location_string]) {
              locations[location_string] = [];
              locations_order.push(location_string);
            }

            locations[location_string].push(client);
          });

          $("#user_clients").append(
              objects_category_view("client", locations_order,
                function (category_name, pane) {
                  var ul = $("<ul class='clients'>"); pane.append(ul);

                  if (typeof locations[category_name] !== 'undefined') {
                    $.each(locations[category_name], function (i, client) {
                      ul.append(template("client", client));
                    });
                  }
                },
                function (category_name) {
                  // Don't need to do anything
                }));
        }
      });
    }
  }
};

function open_popup_window(name, argument) {
  var popup_window = popup_windows[name];

  if (typeof popup_window === 'object') {
    $(".popup_window").remove(); // remove existing popup window

    if (typeof popup_window.get_template_argument == 'function') {
      argument = popup_window.get_template_argument(argument);
    }

    $("body").append(template(popup_window.template_name, argument));

    popup_window.initialize(argument);

    $("#click_catcher, .popup_window").show();

    setTimeout(function () {
      $("#click_catcher, .popup_window").addClass("show");
    }, 0);
  }
}

function close_popup_window() {
  $("#click_catcher, .popup_window").removeClass("show");

  setTimeout(function () {
    $("#click_catcher").hide();
    $(".popup_window").remove();
  }, popup_window_transition_duration);
}

/*
 * Creates a UI element suitable for editing categorized objects.
 *
 * @param {String} object_type
 *   The type of objects this pane will edit. At the moment, it only
 *   affects the resulting CSS class.
 * @param {[String]} categories
 *   A list of categories to present on the left side.
 * @param {Function} view_function
 *   A function taking the category text and the view pane as parameters.
 *   Invoked when a category is selected.
 * @param {Function} [category_create_function]
 *   A function to be invoked when a category is created. If not provided,
 *   the option to create categories will not be shown.
 */
function objects_category_view(object_type, categories, view_function, category_create_function) {
  var category_view = $(template("objects_category_view",
                                 {object_type: object_type
                                 ,show_add:    (category_create_function ? true : false)}));

  var category_click_handler = function () {
    if (!$(this).hasClass("selected")) {
      $(this).siblings().removeClass("selected");
      $(this).addClass("selected");

      view_function($(this).text(), $(".object_view_pane", category_view).empty());
    } else {
      // Unset category entirely.
      $(this).removeClass("selected");
      $(".object_view_pane", category_view).empty();
    }
  }

  var categories_map = {};

  $.each(categories, function (i, category) {

    $(".categories", category_view).append(
      categories_map[category] =
        $("<li>").text(category)
                 .click(category_click_handler));
  });

  // For modifying the view later
  category_view.data("view_function",  view_function);
  category_view.data("categories_map", categories_map);

  // Category creation
  $(".category_buttons .new_category", category_view).click(function () {
    var input          = $("<input type='text'>")
      , categories_map = category_view.data("categories_map");

    var handle_blur = function () {

      // Must not be blank, must not already exist
      if (input.val().replace(/^ | $/g, '').length > 0
      &&  typeof categories_map[input.val()] === 'undefined') {

        // Add click handler
        input.parent().click(category_click_handler);

        // Modify categories map to include new category
        categories_map[input.val()] = input.parent();

        // Not sure if this data directly mutable so I do this anyway
        //  -devyn
        category_view.data("categories_map", categories_map);

        // Set category title to contents
        input.parent().text(input.val());

      } else {
        // If invalid, clear pane and remove category
        $(".object_view_pane").empty();
        input.parent().remove();
      }
    }

    input.blur(function (e) {
      handle_blur();
    });

    input.keypress(function (e) {
      if (e.keyCode === 13 /* enter key */) {
        e.preventDefault();
        handle_blur();
      }
    });

    var li = $("<li>").append(input);

    $(".categories", category_view).append(li);

    // Run click handler to select it
    category_click_handler.apply(li);

    // Let the user type right away
    input.focus();
  });

  return category_view;
}

function objects_category_view_goto(category_view, category) {
  category_view = $(category_view); // just in case we get passed a non-jQuery

  if (category === null) {
    // Unset category entirely.
    $(".categories",       category_view).removeClass("selected");
    $(".object_view_pane", category_view).empty();
  } else {
    var category_item = category_view.data("categories_map")[category];

    if (typeof category_item !== 'undefined') {
      category_item.siblings().removeClass("selected");
      category_item.addClass("selected");

      category_view.data("view_function")(category, $(".object_view_pane", category_view));
    }
  }
}

function task_produce_link(e) {
  open_popup_window("task_produce");
  e.stopPropagation();
}

function update_nav(user_info) {
  $("#nav_right").html(template("nav"));

  if (user_info) {
    $("#nav_right .not_logged_in").remove();

    if (!user_info.is_admin) {
      $("#nav_right .admin").remove();
    }
  } else {
    $("#nav_right .logged_in, #nav_right .admin").remove();
  }

  // Popups
  $.each(["new_task", "user_clients", "user_login"],
      function (i, popup_name) {
        $("#" + popup_name + "_link").click(function (e) {
          open_popup_window(popup_name);
          e.stopPropagation();
        });
      });

  $("#session_delete_link").click(function (e) {
    session_delete();
    e.stopPropagation();
  });
}

function session_delete() {
  $.ajax({
    type: "DELETE",
    url: "/session",
    success: function () {
      post_change_user(null);
    }
  });
}

function connect_to_task_event_stream() {
  if (event_source) {
    event_source.close();
  }

  event_source = new EventSource("/tasks.event-stream");

  event_source.addEventListener("reload",       tasks_reload);
  event_source.addEventListener("taskcreated",  tasks_taskcreated);
  event_source.addEventListener("jobsubmitted", tasks_jobsubmitted);
  event_source.addEventListener("changetotal",  tasks_changetotal);
}

$(function() {
  // compile templates
  $("template.handlebars").each(function() {
    template.handlebars[this.id] = Handlebars.compile($(this).html());
  });

  // establish event source
  connect_to_task_event_stream();

  // register actions
  $("#click_catcher").click(function() {
    close_popup_window();
  });
  $(".popup_window").click(function (e) {
    e.stopPropagation();
  });

  update_nav(window.user_info);
});
