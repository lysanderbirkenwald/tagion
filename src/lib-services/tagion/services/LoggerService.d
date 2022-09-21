/// \file LoggerService.d

/// \page LoggerService

/** @brief Service for handling both text logs and variable logging
 */

module tagion.services.LoggerService;

import std.array;
import std.stdio;
import std.format;
import core.thread;
import core.sys.posix.pthread;
import std.string;
import std.algorithm : any, filter;
import std.algorithm.searching : canFind;

import tagion.basic.Basic : TrustedConcurrency, assumeTrusted;
import tagion.basic.Types : Control;
import tagion.basic.TagionExceptions;
import tagion.GlobalSignals : abort;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONRecord;
import tagion.services.LogSubscriptionService : logSubscriptionServiceTask;
import tagion.services.Options : Options, setOptions, options;
import tagion.logger.Logger;
import tagion.logger.LogRecords;
import tagion.tasks.TaskWrapper;

mixin TrustedConcurrency;

/**
 * \struct LoggerTask
 * Struct represents LoggerService which handles logs and provides passing them to LogSubscriptionService
 */
@safe struct LoggerTask
{
    mixin TaskBasic;

    /** Storage of current log filters, received from LogSubscriptionService */
    LogFilter[] commonLogFilters;
    /** LogSubscriptionService thread id */
    Tid logSubscriptionTid;

    /** Service options */
    Options options;

    /** File for writing text logs */
    File file;
    /** Flag that enables logging output to file */
    bool logging;

    /** Method that helps sending arguments to LogSubscriptionService 
     *      @param args - arbitrary list of arguments to send to service
     */
    void sendToLogSubService(Args...)(Args args)
    {
        if (logSubscriptionTid is Tid.init)
        {
            logSubscriptionTid = locate(options.logSubscription.task_name);
        }

        if (logSubscriptionTid !is Tid.init)
        {
            logSubscriptionTid.send(args);
        }
    }

    /** Method that checks whether given filter matches at least one stored filter 
     *      @param filter - log filter to check
     *      \return boolean result of checking
     */
    bool matchAnyFilter(LogFilter filter)
    {
        return commonLogFilters.any!(f => (f.match(filter)));
    }

    /** Task method that receives logs from Logger and sends them to console, file and LogSubscriptionService
     *      @param filter - log filter that contains info about passed log
     *      @param data - log itself, that can be either TextLog or some HiBONRecord variable
     */
    @TaskMethod void receiveLogs(immutable(LogFilter) filter, immutable(Document) data)
    {
        if (matchAnyFilter(filter))
        {
            sendToLogSubService(filter, data);
        }

        if (filter.isTextLog && data.hasMember(TextLog.label))
        {
            const log_msg = data[TextLog.label].get!string;

            string output;
            if (filter.level is LogLevel.INFO)
            {
                output = format("%s: %s", filter.task_name, log_msg);
            }
            else
            {
                output = format("%s:%s: %s", filter.task_name, filter.level, log_msg);
            }

            if (logging)
            {
                file.writeln(output);
            }

            // Output text log to console
            if (options.logger.to_console)
            {
                writeln(output);
                if (options.logger.flush)
                {
                    assumeTrusted!stdout.flush();
                }
            }

            // Output error log
            if (filter.level & LogLevel.STDERR)
            {
                assumeTrusted!stderr.writefln("%s:%s: %s", filter.task_name, filter.level, log_msg);
            }
        }
    }

    /** Task method that receives filter updates from LogSubscriptionService
     *      @param filters - array of filter updates
     */
    @TaskMethod void receiveFilters(LogFilterArray filters, LogFiltersAction action)
    {
        if (action == LogFiltersAction.ADD)
        {
            commonLogFilters ~= filters.array;
        }
        else
        {
            commonLogFilters = commonLogFilters.filter!(f => filters.array.canFind(f)).array;
        }
    }

    /** Method that triggered when service receives Control.STOP.
     *  Receiving this signal means that LoggerService should be stopped
     */
    void onSTOP()
    {
        stop = true;
        file.writefln("%s stopped ", options.logger.task_name);

        if (abort)
        {
            log.silent = true;
        }
    }

    /** Method that triggered when service receives Control.LIVE.
     *  Receiving this signal means that LogSubscriptionService successfully running
     */
    void onLIVE()
    {
        writeln("LogSubscriptionService is working...");
    }

    /** Method that triggered when service receives Control.STOP.
     *  Receiving this signal means that LogSubsacriptionService successfully stopped
     */
    void onEND()
    {
        writeln("LogSubscriptionService was stopped");
    }

    /** Main method that starts service
     *      @param options - service options
     */
    void opCall(immutable(Options) options)
    {
        this.options = options;
        setOptions(options);

        pragma(msg, "fixme(ib) Pass mask to Logger to not pass not necessary data");

        if (options.logSubscription.enable)
        {
            logSubscriptionTid = spawn(&logSubscriptionServiceTask, options);
        }
        scope (exit)
        {
            import std.stdio;

            if (logSubscriptionTid !is Tid.init)
            {
                logSubscriptionTid.send(Control.STOP);
                if (receiveOnly!Control == Control.END) // TODO: can't receive END when stopping after logservicetest, fix it
                {
                    writeln("Canceled task LogSubscriptionService");
                    writeln("Received END from LogSubscriptionService");
                }
            }
        }

        logging = options.logger.file_name.length != 0;
        if (logging)
        {
            file.open(options.logger.file_name, "w");
            file.writefln("Logger task: %s", options.logger.task_name);
            file.flush;
        }

        ownerTid.send(Control.LIVE);
        while (!stop && !abort)
        {
            receive(&control, &receiveLogs, &receiveFilters);
            if (options.logger.flush && logging)
            {
                file.flush();
            }
        }
    }
}
