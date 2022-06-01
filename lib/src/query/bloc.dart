import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:graphql/client.dart';
import 'package:graphql_flutter_bloc/src/helper.dart';

import 'event.dart';
import 'state.dart';

abstract class QueryBloc<TData>
    extends Bloc<QueryEvent<TData>, QueryState<TData>> {
  GraphQLClient client;
  late ObservableQuery result;
  WatchQueryOptions options;
  StreamSubscription? _subscription;

  QueryBloc({required this.client, required this.options})
      : super(QueryState<TData>.initial()) {
    on<QueryEventRun<TData>>(_run);
    on<QueryEventError<TData>>(_error);
    on<QueryEventLoading<TData>>(_loading);
    on<QueryEventLoaded<TData>>(_loaded);
    on<QueryEventRefetch<TData>>(_refetch);
    on<QueryEventFetchMore<TData>>(_fetchMore);

    result = client.watchQuery<void>(options);

    _subscription = result.stream.listen((QueryResult result) {
      if (state is QueryStateRefetch &&
          result.source == QueryResultSource.cache &&
          options.fetchPolicy == FetchPolicy.cacheAndNetwork) {
        return;
      }

      final exception = result.exception;

      if (exception != null) {
        TData? data;

        if (result.data != null) {
          data = parseData(result.data);
        }

        add(QueryEvent<TData>.error(
          error: exception,
          result: result,
          data: data,
        ));
      }

      if (result.isLoading && result.data == null) {
        add(QueryEvent.loading(result: result));
      }

      if (!result.isLoading && result.data != null) {
        add(
          QueryEvent<TData>.loaded(
            data: parseData(result.data),
            result: result,
          ),
        );
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    result.close();
  }

  void run({
    Map<String, dynamic>? variables,
    Object? optimisticResult,
    FetchPolicy? fetchPolicy,
    ErrorPolicy? errorPolicy,
    CacheRereadPolicy? cacheRereadPolicy,
    Duration? pollInterval,
    bool fetchResults = false,
    bool carryForwardDataOnException = true,
    bool? eagerlyFetchResults,
  }) {
    add(
      QueryEvent<TData>.run(
        variables: variables,
        optimisticResult: optimisticResult,
        fetchPolicy: fetchPolicy,
        errorPolicy: errorPolicy,
        cacheRereadPolicy: cacheRereadPolicy,
        pollInterval: pollInterval,
        fetchResults: fetchResults,
        carryForwardDataOnException: carryForwardDataOnException,
        eagerlyFetchResults: eagerlyFetchResults,
      ),
    );
  }

  void refetch({
    Map<String, dynamic>? variables,
    Object? optimisticResult,
    FetchPolicy? fetchPolicy,
    ErrorPolicy? errorPolicy,
    CacheRereadPolicy? cacheRereadPolicy,
    Duration? pollInterval,
    bool fetchResults = false,
    bool carryForwardDataOnException = true,
    bool? eagerlyFetchResults,
  }) {
    add(
      QueryEvent<TData>.refetch(
        variables: variables,
        optimisticResult: optimisticResult,
        fetchPolicy: fetchPolicy,
        errorPolicy: errorPolicy,
        cacheRereadPolicy: cacheRereadPolicy,
        pollInterval: pollInterval,
        fetchResults: fetchResults,
        carryForwardDataOnException: carryForwardDataOnException,
        eagerlyFetchResults: eagerlyFetchResults,
      ),
    );
  }

  bool shouldFetchMore(int i, int threshold) => false;

  bool get isFetchingMore => state is QueryStateFetchMore;

  bool get isLoading => state is QueryStateLoading;

  bool get isLoaded => state is QueryStateLoaded;

  bool get isRefetching => state is QueryStateRefetch;

  TData parseData(Map<String, dynamic>? data);

  bool get hasData => (state is QueryStateLoaded<TData> ||
      state is QueryStateFetchMore<TData> ||
      state is QueryStateRefetch<TData>);

  bool get hasError => state is QueryStateError<TData>;

  String? get getError => hasError
      ? parseOperationException((state as QueryStateError<TData>).error)
      : null;

  FutureOr<void> _run(
    QueryEventRun<TData> event,
    Emitter<QueryState<TData>> emit,
  ) async {
    result.options = _updateOptions(
      variables: event.variables,
      optimisticResult: event.optimisticResult,
      fetchPolicy: event.fetchPolicy,
      errorPolicy: event.errorPolicy,
      cacheRereadPolicy: event.cacheRereadPolicy,
      pollInterval: event.pollInterval,
      fetchResults: event.fetchResults,
      carryForwardDataOnException: event.carryForwardDataOnException,
      eagerlyFetchResults: event.eagerlyFetchResults,
    );

    result.fetchResults();
  }

  WatchQueryOptions _updateOptions({
    Map<String, dynamic>? variables,
    Object? optimisticResult,
    FetchPolicy? fetchPolicy,
    ErrorPolicy? errorPolicy,
    CacheRereadPolicy? cacheRereadPolicy,
    Duration? pollInterval,
    bool fetchResults = false,
    bool carryForwardDataOnException = true,
    bool? eagerlyFetchResults,
  }) {
    return WatchQueryOptions(
      document: options.document,
      operationName: options.operationName,
      variables: variables ?? options.variables,
      fetchPolicy: fetchPolicy ?? options.fetchPolicy,
      errorPolicy: errorPolicy ?? options.errorPolicy,
      cacheRereadPolicy: cacheRereadPolicy ?? options.cacheRereadPolicy,
      optimisticResult: optimisticResult ?? options.optimisticResult,
      pollInterval: pollInterval ?? options.pollInterval,
      fetchResults: fetchResults,
      carryForwardDataOnException: carryForwardDataOnException,
      eagerlyFetchResults: eagerlyFetchResults ?? options.eagerlyFetchResults,
      context: options.context,
      parserFn: options.parserFn,
    );
  }

  FutureOr<void> _error(
    QueryEventError<TData> event,
    Emitter<QueryState<TData>> emit,
  ) async {
    TData? data;

    if (event.result.data != null) {
      data = parseData(event.result.data);
    }

    emit(QueryState<TData>.error(
      error: event.error,
      result: event.result,
      data: data,
    ));
  }

  FutureOr<void> _loading(
    QueryEventLoading<TData> event,
    Emitter<QueryState<TData>> emit,
  ) async {
    emit(QueryState.loading(result: event.result));
  }

  FutureOr<void> _loaded(
    QueryEventLoaded<TData> event,
    Emitter<QueryState<TData>> emit,
  ) async {
    emit(QueryState<TData>.loaded(data: event.data, result: event.result));
  }

  FutureOr<void> _refetch(
    QueryEventRefetch<TData> event,
    Emitter<QueryState<TData>> emit,
  ) async {
    emit(
      QueryState<TData>.refetch(
        data: state.maybeWhen(
          loaded: (data, _) => data,
          orElse: () => null,
        ),
        result: null,
      ),
    );

    result.options = _updateOptions(
      variables: event.variables,
      optimisticResult: event.optimisticResult,
      fetchPolicy: event.fetchPolicy,
      errorPolicy: event.errorPolicy,
      cacheRereadPolicy: event.cacheRereadPolicy,
      pollInterval: event.pollInterval,
      fetchResults: event.fetchResults,
      carryForwardDataOnException: event.carryForwardDataOnException,
      eagerlyFetchResults: event.eagerlyFetchResults,
    );

    result.refetch();
  }

  FutureOr<void> _fetchMore(
    QueryEventFetchMore<TData> event,
    Emitter<QueryState<TData>> emit,
  ) async {
    emit(
      QueryState<TData>.fetchMore(
        data: state.maybeWhen(
          loaded: (data, _) => data,
          orElse: () => null,
        ),
        result: null,
      ),
    );

    result.fetchMore(event.options);
  }
}
