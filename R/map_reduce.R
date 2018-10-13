#' @title Create a plan that maps a function to a grid of arguments.
#' @description `map_plan()` is like `pmap_df()` from the `purrr` package.
#'   It takes a function name and a grid of arguments, and it
#'   writes out all the commands calls to apply the function to
#'   each row of arguments.
#' @export
#' @seealso drake_plan, reduce_by, gather_by, reduce_plan, gather_plan,
#'   evaluate_plan, expand_plan
#' @return A workflow plan data frame
#' @param args a data frame (or better yet, a `tibble`)
#'   of function arguments to `fun`.
#'   Here, the column names should be the names of the arguments
#'   of `fun`, and each row of `args` corresponds to a
#'   call to `fun`.
#' @param fun name of a function to apply the arguments
#'   row-by-row. Supply a symbol if `character_only` is
#'   `FALSE` and a character scalar otherwise.
#' @param id name of an optional column in `args`
#'   giving the names of the targets. If not supplied,
#'   target names will be generated automatically.
#'   `id` should be a symbol if `character_only` is `FALSE`
#'   and a character scalar otherwise.
#' @param character_only logical, whether to interpret
#'   the `fun` and `id` arguments as character scalars or symbols.
#' @examples
#' # For the full tutorial, visit
#' # https://ropenscilabs.github.io/drake-manual/plans.html#map_plan.
#' my_model_fit <- function(x1, x2, data){
#'   lm(as.formula(paste("mpg ~", x1, "+", x1)), data = data)
#' }
#' covariates <- setdiff(colnames(mtcars), "mpg")
#' args <- tibble::as_tibble(t(combn(covariates, 2)))
#' colnames(args) <- c("x1", "x2")
#' args$data <- "mtcars"
#' args$data <- rlang::syms(args$data)
#' args$id <- paste0("fit_", args$x1, "_", args$x2)
#' args
#' plan <- map_plan(args, my_model_fit)
#' plan
#' cache <- storr::storr_environment()
#' make(plan, verbose = FALSE, cache = cache)
#' readd(fit_cyl_disp, cache = cache)
map_plan <- function(args, fun, id = "id", character_only = FALSE){
  args <- as_tibble(args)
  if (!character_only){
    fun <- as.character(substitute(fun))
    id <- as.character(substitute(id))
  }
  if (id %in% colnames(args)){
    target <- args[[id]]
    args <- args[, setdiff(colnames(args), id)]
  } else {
    target <- paste0(
      fun, "_",
      apply(X = args, MARGIN = 1, FUN = digest::digest, algo = "murmur32")
    )
  }
  command <- purrr::pmap_chr(
    .l = args,
    .f = function(...){
      list(as.name(fun), ...) %>%
        as.call() %>%
        rlang::expr_text()
    }
  )
  tibble::tibble(target = target, command = command) %>%
    sanitize_plan()
}

#' @title Write commands to combine several targets into one
#'   or more overarching targets.
#' @description Creates a new workflow plan data frame with a single new
#' target. This new target is a list, vector, or other aggregate of
#' a collection of existing targets in another workflow plan data frame.
#' @export
#' @seealso drake_plan, map_plan, reduce_by, gather_by, reduce_plan,
#'   evaluate_plan, expand_plan
#' @return A workflow plan data frame that aggregates multiple
#'   prespecified targets into one additional target downstream.
#' @param plan workflow plan data frame of prespecified targets
#' @param target name of the new aggregated target
#' @param gather function used to gather the targets. Should be
#'   one of `list(...)`, `c(...)`, `rbind(...)`, or similar.
#' @examples
#' # Workflow plan for datasets:
#' datasets <- drake_plan(
#'   small = simulate(5),
#'   large = simulate(50))
#' # Create a new target that brings the datasets together.
#' gather_plan(datasets, target = "my_datasets")
#' # This time, the new target just appends the rows of 'small' and 'large'
#' # into a single matrix or data frame.
#' gathered <- gather_plan(
#'   datasets, target = "aggregated_data", gather = "rbind"
#' )
#' gathered
#' # For the complete workflow plan, row bind the pieces together.
#' my_plan <- rbind(datasets, gathered)
#' my_plan
gather_plan <- function(
  plan = NULL,
  target = "target",
  gather = "list"
){
  command <- paste(plan$target, "=", plan$target)
  command <- paste(command, collapse = ", ")
  command <- paste0(gather, "(", command, ")")
  tibble(target = target, command = command)
}

#' @title Gather multiple groupings of targets
#' @description Perform several calls to [gather_plan()]
#'   based on groupings from columns in the plan,
#'   and then row-bind the new targets to the plan.
#' @export
#' @seealso drake_plan, map_plan, reduce_by, reduce_plan,
#'   gather_plan, evaluate_plan, expand_plan
#' @inheritParams gather_plan
#' @param ... Symbols, columns of `plan` to define target groupings
#'   passed to `dplyr::group_by()`.
#'   A [gather_plan()] call is applied for each grouping.
#'   Groupings with all `NA`s in the selector variables are ignored.
#' @param prefix character, prefix for naming the new targets.
#'   Suffixes are generated from the values of the columns
#'   specified in `...`.
#' @examples
#' plan <- drake_plan(
#'   data = get_data(),
#'   informal_look = inspect_data(data, mu = mu__),
#'   bayes_model = bayesian_model_fit(data, prior_mu = mu__)
#' )
#' plan <- evaluate_plan(plan, rules = list(mu__ = 1:2), trace = TRUE)
#' gather_by(plan, mu___from, gather = "dplyr::bind_rows")
#' gather_by(plan, mu__, mu___from, prefix = "x")
#' reduce_by(plan, mu___from, begin = "list(", end = ")", op = ", ")
#' reduce_by(plan, mu__, mu___from)
gather_by <- function(plan, ..., prefix = "target", gather = "list"){
  . <- NULL
  gathered <- dplyr::group_by(plan, ...) %>%
    dplyr::do(gather_plan(plan = ., target = prefix, gather = gather))
  cols <- dplyr::select(gathered, ...)
  suffix <- purrr::pmap_chr(cols, .f = paste, sep = "_")
  gathered$target <- paste(gathered$target, suffix, sep = "_")
  keep <- apply(cols, 1, function(x){
    !all(is.na(x))
  })
  bind_plans(plan, gathered[keep, ])
}

#' @title Write commands to reduce several targets down to one.
#' @description Creates a new workflow plan data frame with the
#'   commands to do a reduction (i.e. to repeatedly apply a binary
#'   operator to pairs of targets to produce one target).
#' @export
#' @seealso drake_plan, map_plan, reduce_by, gather_by,
#'   gather_plan, evaluate_plan, expand_plan
#' @return A workflow plan data frame that aggregates multiple
#'   prespecified targets into one additional target downstream.
#' @param plan workflow plan data frame of prespecified targets
#' @param target name of the new reduced target
#' @param begin character, code to place at the beginning
#'   of each step in the reduction
#' @param op binary operator to apply in the reduction
#' @param end character, code to place at the end
#'   of each step in the reduction
#' @param pairwise logical, whether to create multiple
#'   new targets, one for each pair/step in the reduction (`TRUE`),
#'   or to do the reduction all in one command.
#' @examples
#' # Workflow plan for datasets:
#' x_plan <- evaluate_plan(
#'   drake_plan(x = VALUE),
#'   wildcard = "VALUE",
#'   values = 1:8
#' )
#' # Create a new target from the sum of the others.
#' reduce_plan(x_plan, target = "x_sum", pairwise = FALSE)
#' # For memory efficiency and parallel computing,
#' # reduce pairwise:
#' reduce_plan(x_plan, target = "x_sum", pairwise = TRUE)
#' # Optionally define your own function and use it as the
#' # binary operator in the reduction.
#' x_plan <- evaluate_plan(
#'   drake_plan(x = VALUE),
#'   wildcard = "VALUE",
#'   values = 1:9
#' )
#' x_plan
#' reduce_plan(
#'   x_plan, target = "x_sum", pairwise = TRUE,
#'   begin = "fun(", op = ", ", end = ")"
#' )
reduce_plan <- function(
  plan = NULL,
  target = "target",
  begin = "",
  op = " + ",
  end = "",
  pairwise = TRUE
){
  if (pairwise){
    pairs <- reduction_pairs(
      x = plan$target,
      base_name = paste0(target, "_")
    )
    pairs$names[nrow(pairs)] <- target
    tibble(
      target = pairs$names,
      command = paste0(begin, pairs$odds, op, pairs$evens, end)
    )
  } else {
    command <- Reduce(
      x = plan$target,
      f = function(x, y){
        paste0(begin, x, op, y, end)
      }
    )
    tibble(target = target, command = command)
  }
}

#' @title Reduce multiple groupings of targets
#' @description Perform several calls to [reduce_plan()]
#'   based on groupings from columns in the plan,
#'   and then row-bind the new targets to the plan.
#' @export
#' @seealso drake_plan, map_plan, gather_by, reduce_plan,
#'   gather_plan, evaluate_plan, expand_plan
#' @inheritParams reduce_plan
#' @param ... Symbols, columns of `plan` to define target groupings
#'   passed to `dplyr::group_by()`.
#'   A [reduce_plan()] call is applied for each grouping.
#'   Groupings with all `NA`s in the selector variables are ignored.
#' @param prefix character, prefix for naming the new targets.
#'   Suffixes are generated from the values of the columns
#'   specified in `...`.
#' @examples
#' plan <- drake_plan(
#'   data = get_data(),
#'   informal_look = inspect_data(data, mu = mu__),
#'   bayes_model = bayesian_model_fit(data, prior_mu = mu__)
#' )
#' plan <- evaluate_plan(plan, rules = list(mu__ = 1:2), trace = TRUE)
#' gather_by(plan, mu___from, gather = "dplyr::bind_rows")
#' gather_by(plan, mu__, mu___from, prefix = "x")
#' reduce_by(plan, mu___from, begin = "list(", end = ")", op = ", ")
#' reduce_by(plan, mu__, mu___from)
reduce_by <- function(
  plan,
  ...,
  prefix = "target",
  begin = "",
  op = " + ",
  end = "",
  pairwise = TRUE
){
  . <- NULL
  reduced <- dplyr::group_by(plan, ...) %>%
    dplyr::do(
      reduce_plan(
        plan = .,
        target = prefix,
        begin = begin,
        op = op,
        end = end,
        pairwise = pairwise
      )
    )
  cols <- dplyr::select(reduced, ...)
  suffix <- purrr::pmap_chr(cols, .f = paste, sep = "_")
  reduced$target <- paste(reduced$target, suffix, sep = "_")
  keep <- apply(cols, 1, function(x){
    !all(is.na(x))
  })
  bind_plans(plan, reduced[keep, ])
}

reduction_pairs <- function(x, pairs = NULL, base_name = "reduced_"){
  if (length(x) < 2){
    return(pairs)
  }
  evens <- x[seq(from = 2, to = length(x), by = 2)]
  odds <- x[seq(from = 1, to = length(x), by = 2)]
  names <- new_x <- paste0(base_name, seq_along(odds) + (nrow(pairs) %||% 0))
  if (length(odds) > length(evens)){
    evens[length(evens) + 1] <- names[1]
    new_x <- new_x[-1]
  }
  new_pairs <- data.frame(
    names = names, odds = odds, evens = evens,
    stringsAsFactors = FALSE
  )
  reduction_pairs(
    x = new_x,
    pairs = rbind(pairs, new_pairs),
    base_name = base_name
  )
}